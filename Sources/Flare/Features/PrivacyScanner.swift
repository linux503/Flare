import AppKit
import Vision

enum PrivacyKind: String, CaseIterable {
    case apiKey
    case mnemonic
    case privateKey
    case wallet
    case bankCard
    case idDocument
    case email
    case phone
    case customer
    case qrCode
    case cookieToken

    var title: String {
        switch self {
        case .apiKey: return "API Key"
        case .mnemonic: return "助记词"
        case .privateKey: return "私钥"
        case .wallet: return "钱包地址"
        case .bankCard: return "银行卡"
        case .idDocument: return "身份证件"
        case .email: return "邮箱"
        case .phone: return "电话"
        case .customer: return "客户资料"
        case .qrCode: return "二维码"
        case .cookieToken: return "Cookie / Token"
        }
    }
}

struct PrivacyFinding {
    let kind: PrivacyKind
    /// Vision 归一化矩形，原点在左下
    let box: CGRect
}

enum PrivacyScanner {
    static func scan(image: NSImage) async -> [PrivacyFinding] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        // 隐私门控用缩小图 + 快速 OCR，编辑器「OCR→TXT」仍走 accurate
        let scanImage = downscaleForScan(cgImage, maxEdge: 1600) ?? cgImage
        async let textHits = recognizeText(scanImage)
        async let codeHits = detectCodes(scanImage)
        let merged = await textHits + codeHits
        return dedupe(merged)
    }

    static func redact(_ image: NSImage, findings: [PrivacyFinding]) -> NSImage {
        let size = image.size
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        let padX = max(1.5, min(4, size.width * 0.0025))
        let padY = max(1.0, min(3, size.height * 0.0025))
        for finding in findings {
            var rect = CGRect(
                x: finding.box.origin.x * size.width,
                y: finding.box.origin.y * size.height,
                width: finding.box.width * size.width,
                height: finding.box.height * size.height
            ).insetBy(dx: -padX, dy: -padY)
            rect = rect.intersection(CGRect(origin: .zero, size: size))
            guard rect.width > 1.5, rect.height > 1.5 else { continue }
            // 文字遮挡：略扁的圆角条，贴合字高，避免整行被大块盖住
            let radius = min(4, max(2, rect.height * 0.28))
            NSColor.black.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        canvas.unlockFocus()
        return canvas
    }

    static func summary(of findings: [PrivacyFinding]) -> String {
        let titles = PrivacyKind.allCases.filter { kind in
            findings.contains { $0.kind == kind }
        }.map(\.title)
        return titles.joined(separator: "、")
    }

    // MARK: - Vision

    private static func recognizeText(_ cgImage: CGImage) async -> [PrivacyFinding] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var hits: [PrivacyFinding] = []
                for observation in observations {
                    guard let text = observation.topCandidates(1).first else { continue }
                    hits.append(contentsOf: match(text: text, fallback: observation.boundingBox))
                }
                hits.append(contentsOf: matchAcrossLines(observations))
                continuation.resume(returning: hits)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    /// 长边超过 maxEdge 时缩小，显著降低 Vision 耗时；归一化框比例不变。
    private static func downscaleForScan(_ image: CGImage, maxEdge: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > maxEdge else { return nil }
        let scale = CGFloat(maxEdge) / CGFloat(longest)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private static func detectCodes(_ cgImage: CGImage) async -> [PrivacyFinding] {
        await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, _ in
                let codes = (request.results as? [VNBarcodeObservation]) ?? []
                let hits = codes.map { PrivacyFinding(kind: .qrCode, box: $0.boundingBox) }
                continuation.resume(returning: hits)
            }
            request.symbologies = [.qr, .aztec, .dataMatrix, .pdf417]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Match

    private static func match(text: VNRecognizedText, fallback: CGRect) -> [PrivacyFinding] {
        let raw = text.string
        var hits: [PrivacyFinding] = []
        func add(_ kind: PrivacyKind, _ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            let box: CGRect
            if let swiftRange = Range(range, in: raw),
               let observed = try? text.boundingBox(for: swiftRange) {
                box = observed.boundingBox
            } else if let approx = approximateBox(for: range, in: raw, lineBox: fallback) {
                box = approx
            } else {
                // 整行兜底时收窄到中间条带，减少误挡旁边无关字
                box = fallback.insetBy(dx: fallback.width * 0.02, dy: fallback.height * 0.12)
            }
            guard box.width > 0.002, box.height > 0.002 else { return }
            hits.append(PrivacyFinding(kind: kind, box: box))
        }

        let ns = raw as NSString
        for pattern in secretPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.regex, options: pattern.options) else { continue }
            for match in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
                let range = match.range(at: match.numberOfRanges > 1 ? 1 : 0)
                guard range.location != NSNotFound else { continue }
                let snippet = ns.substring(with: range)
                if pattern.kind == .bankCard, !isBankCard(snippet) { continue }
                if pattern.kind == .idDocument {
                    let idLike = snippet.range(of: #"\d{17}[\dXx]"#, options: .regularExpression) != nil
                    if idLike, !isChineseID(snippet) { continue }
                }
                if pattern.kind == .wallet, snippet.lowercased().hasPrefix("0x"), snippet.count != 42 { continue }
                if pattern.kind == .phone, !isMobilePhone(snippet) { continue }
                if pattern.kind == .email, !isPlausibleEmail(snippet) { continue }
                if pattern.kind == .customer, snippet.count < 2 { continue }
                add(pattern.kind, range)
            }
        }
        return hits
    }

    /// OCR 给不出子串框时，按字符占比估算敏感片段位置
    private static func approximateBox(for range: NSRange, in raw: String, lineBox: CGRect) -> CGRect? {
        let ns = raw as NSString
        guard range.location != NSNotFound, range.length > 0, ns.length > 0 else { return nil }
        let total = CGFloat(ns.length)
        let start = CGFloat(range.location) / total
        let end = CGFloat(range.location + range.length) / total
        let width = max(0.01, (end - start) * lineBox.width)
        return CGRect(
            x: lineBox.minX + start * lineBox.width,
            y: lineBox.minY + lineBox.height * 0.08,
            width: width,
            height: lineBox.height * 0.84
        )
    }

    /// 助记词：跨行拼成词序列后，只遮挡真正落在 12/24 词窗口里的行
    private static func matchAcrossLines(_ observations: [VNRecognizedTextObservation]) -> [PrivacyFinding] {
        struct WordHit {
            let word: String
            let box: CGRect
        }
        var sequence: [WordHit] = []
        var labeledBoxes: [CGRect] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = candidate.string
            if line.range(
                of: #"(助记词|seed\s*phrase|mnemonic|recovery\s*phrase)"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                labeledBoxes.append(observation.boundingBox)
            }
            let parts = line.lowercased().split { !$0.isLetter }.map(String.init)
            for part in parts where (3...8).contains(part.count) {
                // 尽量用整词框；失败则用该行框的横向切片
                let box: CGRect
                if let range = line.range(of: part, options: .caseInsensitive),
                   let observed = try? candidate.boundingBox(for: range) {
                    box = observed.boundingBox
                } else {
                    box = observation.boundingBox
                }
                sequence.append(WordHit(word: part, box: box))
            }
        }

        var hits: [PrivacyFinding] = []
        let windows = [12, 15, 18, 21, 24]
        for size in windows where sequence.count >= size {
            for i in 0...(sequence.count - size) {
                let slice = Array(sequence[i..<(i + size)])
                guard slice.allSatisfy({ mnemonicWords.contains($0.word) }) else { continue }
                for item in slice {
                    hits.append(PrivacyFinding(kind: .mnemonic, box: item.box))
                }
            }
        }
        // 有「助记词」标签但词数不足时：只遮挡标签附近、且已命中词表的词，不整页涂黑
        if hits.isEmpty, !labeledBoxes.isEmpty {
            let known = sequence.filter { mnemonicWords.contains($0.word) }
            if known.count >= 6 {
                for item in known.prefix(24) {
                    hits.append(PrivacyFinding(kind: .mnemonic, box: item.box))
                }
            }
        }
        return hits
    }

    private static func isMobilePhone(_ raw: String) -> Bool {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 11, digits.hasPrefix("1") else { return false }
        guard let second = digits.dropFirst().first, ("3"..."9").contains(second) else { return false }
        return true
    }

    private static func isPlausibleEmail(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        guard lower.contains("@"), lower.contains(".") else { return false }
        // 过滤明显占位/示例
        if lower.contains("example.com") || lower.contains("email@") || lower.hasPrefix("your@") { return false }
        return lower.count >= 6 && lower.count <= 80
    }

    private static func isBankCard(_ raw: String) -> Bool {
        let digits = raw.filter(\.isNumber)
        guard (13...19).contains(digits.count) else { return false }
        guard luhn(digits) else { return false }
        // 分组卡号更可靠；无分隔时限制为常见长度，降低订单号误伤
        if raw.range(of: #"\d{4}([ -]\d{4}){2,4}"#, options: .regularExpression) != nil {
            return true
        }
        guard (15...19).contains(digits.count) else { return false }
        return Set(digits).count > 3
    }

    private static func luhn(_ digits: String) -> Bool {
        var sum = 0
        var alt = false
        for ch in digits.reversed() {
            guard let n = ch.wholeNumberValue else { return false }
            var d = n
            if alt {
                d *= 2
                if d > 9 { d -= 9 }
            }
            sum += d
            alt.toggle()
        }
        return sum % 10 == 0
    }

    private static func isChineseID(_ raw: String) -> Bool {
        let cleaned = raw.filter { $0.isNumber || $0 == "X" || $0 == "x" }.uppercased()
        guard cleaned.count == 18 else { return false }
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        let checks = Array("10X98765432")
        var sum = 0
        for (i, ch) in cleaned.dropLast().enumerated() {
            guard let n = ch.wholeNumberValue else { return false }
            sum += n * weights[i]
        }
        return cleaned.last == checks[sum % 11]
    }

    private static func dedupe(_ findings: [PrivacyFinding]) -> [PrivacyFinding] {
        var kept: [PrivacyFinding] = []
        for finding in findings {
            let overlaps = kept.contains { existing in
                existing.kind == finding.kind && existing.box.intersects(finding.box.insetBy(dx: -0.01, dy: -0.01))
            }
            if !overlaps { kept.append(finding) }
        }
        return kept
    }

    private struct Pattern {
        let kind: PrivacyKind
        let regex: String
        var options: NSRegularExpression.Options = []
    }

    private static let secretPatterns: [Pattern] = [
        Pattern(kind: .apiKey, regex: #"(?i)\b(sk-[a-zA-Z0-9]{20,}|sk-proj-[a-zA-Z0-9_-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z\-_]{35}|ghp_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{22,}|xox[baprs]-[a-zA-Z0-9-]{10,}|sk_live_[a-zA-Z0-9]{24,}|rk_live_[a-zA-Z0-9]{24,})"#),
        Pattern(kind: .apiKey, regex: #"(?i)(?:api[_-]?key|secret[_-]?key|access[_-]?key)\s*[:=]\s*['"]?([A-Za-z0-9_\-]{20,})"#),
        Pattern(kind: .privateKey, regex: #"(?i)-----BEGIN [A-Z ]*PRIVATE KEY-----"#),
        Pattern(kind: .privateKey, regex: #"\b(0x[a-fA-F0-9]{64})\b"#),
        Pattern(kind: .privateKey, regex: #"\b([5KL][1-9A-HJ-NP-Za-km-z]{50,51})\b"#),
        Pattern(kind: .wallet, regex: #"\b(0x[a-fA-F0-9]{40})\b"#),
        Pattern(kind: .wallet, regex: #"\b(bc1[a-z0-9]{25,62})\b"#),
        Pattern(kind: .wallet, regex: #"\b([13][a-km-zA-HJ-NP-Z1-9]{25,34})\b"#),
        Pattern(kind: .wallet, regex: #"\b(T[1-9A-HJ-NP-Za-km-z]{33})\b"#),
        Pattern(kind: .bankCard, regex: #"\b((?:\d{4}[ -]){3}\d{4}(?:[ -]\d{1,4})?)\b"#),
        Pattern(kind: .bankCard, regex: #"(?i)(?:卡号|银行卡|credit\s*card|card\s*(?:no|number))\s*[:：]?\s*((?:\d[ -]?){13,19})"#),
        Pattern(kind: .bankCard, regex: #"\b(\d{16}|\d{19})\b"#),
        Pattern(kind: .idDocument, regex: #"(?<!\d)(\d{17}[\dXx])(?!\d)"#),
        Pattern(kind: .idDocument, regex: #"(?i)(?:护照|passport)\s*[:：]?\s*([A-Z0-9]{8,9})"#),
        Pattern(kind: .email, regex: #"(?i)\b([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,24})\b"#),
        Pattern(kind: .phone, regex: #"(?<!\d)(?:\+?86[-\s]?)?(1[3-9]\d{9})(?!\d)"#),
        Pattern(kind: .customer, regex: #"(?:客户|会员|开户)(?:姓名|名称|编号|资料|信息)\s*[:：]\s*(\S{2,24})"#),
        Pattern(kind: .cookieToken, regex: #"(eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,})"#),
        Pattern(kind: .cookieToken, regex: #"(?i)(?:cookie|session[_-]?id|csrf[_-]?token|access[_-]?token|refresh[_-]?token|bearer)\s*[:=]\s*['"]?([A-Za-z0-9._~+/=%-]{16,})"#)
    ]

    /// 常见 BIP39 词，用来确认 12/24 词序列，避免把普通英文句子当成助记词
    private static let mnemonicWords: Set<String> = {
        let raw = """
        abandon ability able about above absent absorb abstract absurd abuse access accident account accuse achieve acid \
        acoustic acquire across act action actor actress actual adapt add addict address adjust admit adult advance advice \
        aerobic affair afford afraid again age agent agree ahead aim air airport aisle alarm album alcohol alert alien all \
        alley allow almost alone alpha already also alter always amateur amazing among amount amused analyst anchor ancient \
        anger angle angry animal ankle announce annual another answer antenna antique anxiety any apart apology appear apple \
        approve april arch arctic area arena argue arm armed armor army around arrange arrest arrive arrow art artefact artist \
        artwork ask aspect assault asset assist assume asthma athlete atom attack attend attitude attract auction audit \
        august aunt author auto autumn average avocado avoid awake aware away awesome awful awkward axis baby bachelor bacon \
        badge bag balance balcony ball bamboo banana banner bar barely bargain barrel base basic basket battle beach bean \
        beauty because become beef before begin behave behind believe below belt bench benefit best betray better between \
        beyond bicycle bid bike bind biology bird birth bitter black blade blame blanket blast bleak bless blind blood blossom \
        blouse blue blur blush board boat body boil bomb bone bonus book boost border boring borrow boss bottom bounce box \
        boy bracket brain brand brass brave bread breeze brick bridge brief bright bring brisk broccoli broken bronze broom \
        brother brown brush bubble buddy budget buffalo build bulb bulk bullet bundle bunker burden burger burst bus business \
        busy butter buyer buzz cabbage cabin cable cactus cage cake call calm camera camp can canal cancel candy cannon canoe \
        canvas canyon capable capital captain car carbon card cargo carpet carry cart case cash casino castle casual cat \
        catalog catch category cattle caught cause caution cave ceiling celery cement census century cereal certain chair \
        chalk champion change chaos chapter charge chase chat cheap check cheese chef cherry chest chicken chief child chimney \
        choice choose chronic chuckle chunk churn cigar cinnamon circle citizen city civil claim clap clarify claw clay clean \
        clerk clever click client cliff climb clinic clip clock clog close cloth cloud clown club clump cluster clutch coach \
        coast coconut code coffee coil coin collect color column combine come comfort comic common company concert conduct \
        confirm congress connect consider control convince cook cool copper copy coral core corn correct cost cotton couch \
        country couple course cousin cover coyote crack cradle craft cram crane crash crater crawl crazy cream credit creek \
        crew cricket crime crisp critic crop cross crouch crowd crucial cruel cruise crumble crunch crush cry crystal cube \
        culture cup cupboard curious current curtain curve cushion custom cute cycle dad damage damp dance danger daring dash \
        daughter dawn day deal debate debris decade december decide decline decorate decrease deer defense define defy degree \
        delay deliver demand demise denial dentist deny depart depend deposit depth deputy derive describe desert design desk \
        despair destroy detail detect develop device devote diagram dial diamond diary dice diesel diet differ digital dignity \
        dilemma dinner dinosaur direct dirt disagree discover disease dish dismiss disorder display distance divert divide \
        divorce dizzy doctor document dog doll dolphin domain donate donkey donor door dose double dove draft dragon drama \
        drastic draw dream dress drift drill drink drip drive drop drum dry duck dumb dune during dust dutch duty dwarf dynamic \
        eager eagle early earn earth easily east easy echo ecology economy edge edit educate effort egg eight either elbow \
        elder electric elegant element elephant elevator elite else embark embody embrace emerge emotion employ empower empty \
        enable enact end endless endorse enemy energy enforce engage engine enhance enjoy enlist enough enrich enroll ensure \
        enter entire entry envelope episode equal equip era erase erode erosion error erupt escape essay essence estate eternal \
        ethics evidence evil evoke evolve exact example excess exchange excite exclude excuse execute exercise exhaust exhibit \
        exile exist exit exotic expand expect expire explain expose express extend extra eye eyebrow fabric face faculty fade \
        faint faith fall false fame family famous fan fancy fantasy farm fashion fat fatal father fatigue fault favorite feature \
        february federal fee feed feel female fence festival fetch fever few fiber fiction field figure file film filter final \
        find fine finger finish fire firm first fiscal fish fit fitness fix flag flame flash flat flavor flee flight flip float \
        flock floor flower fluid flush fly foam focus fog foil fold follow food foot force forest forget fork fortune forum \
        forward fossil foster found fox fragile frame frequent fresh friend fringe frog front frost frown frozen fruit fuel \
        fun funny furnace fury future gadget gain galaxy gallery game gap garage garbage garden garlic garment gas gasp gate \
        gather gauge gaze general genius genre gentle genuine gesture ghost giant gift giggle ginger giraffe girl give glad \
        glance glare glass glide glimpse globe gloom glory glove glow glue goat goddess gold good goose gorilla gospel gossip \
        govern gown grab grace grain grant grape grass gravity great green grid grief grit grocery group grow grunt guard \
        guess guide guilt guitar gun gym habit hair half hammer hamster hand happy harbor hard harsh harvest hat have hawk \
        hazard head health heart heavy hedgehog height hello helmet help hen hero hidden high hill hint hip hire history hobby \
        hockey hold hole holiday hollow home honey hood hope horn horror horse hospital host hotel hour hover hub huge human \
        humble humor hundred hungry hunt hurdle hurry hurt husband hybrid ice icon idea identify idle ignore ill illegal image \
        imitate immense immune impact impose improve impulse inch include income increase index indicate indoor industry infant \
        inflict inform inhale inherit initial inject injury inmate inner innocent input inquiry insane insect inside inspire \
        install intact interest into invest invite involve iron island isolate issue item ivory jacket jaguar jar jazz jealous \
        jeans jelly jewel job join joke journey joy judge juice jump jungle junior junk just kangaroo keen keep ketchup key \
        kick kid kidney kind kingdom kiss kit kitchen kite kitten kiwi knee knife knock know lab label labor ladder lady lake \
        lamp language laptop large later latin laugh laundry lava law lawn lawsuit layer lazy leader leaf learn leave lecture \
        left leg legal legend leisure lemon lend length lens leopard lesson letter level liar liberty library license life \
        lift light like limb limit link lion liquid list little live lizard load loan lobster local lock logic lonely long \
        loop lottery loud lounge love loyal lucky luggage lumber lunar lunch luxury lyrics machine mad magic magnet maid mail \
        main major make mammal man manage mandate mango mansion manual maple marble march margin marine market marriage mask \
        mass master match material math matrix matter maximum maze meadow mean measure meat mechanic medal media melody melt \
        member memory mention menu mercy merge merit merry mesh message metal method middle midnight milk million mimic mind \
        minimum minor minute miracle mirror misery miss mistake mix mixed mixture mobile model modify mom moment monitor monkey \
        monster month moon moral more morning mosquito mother motion motor mountain mouse move movie much muffin mule multiply \
        muscle museum mushroom music must mutual myself mystery myth naive name napkin narrow nasty nation nature near neck \
        need negative neglect neither nephew nerve nest net network neutral never news next nice night noble noise nominee \
        noodle normal north nose notable note nothing notice novel now nuclear number nurse nut oak obey object oblige obscure \
        observe obtain obvious occur ocean october odor off offer office often oil okay old olive olympic omit once one onion \
        online only open opera opinion oppose option orange orbit orchard order ordinary organ orient original orphan ostrich \
        other outdoor outer output outside oval oven over own owner oxygen oyster ozone pact paddle page pair palace palm \
        panda panel panic panther paper parade parent park parrot party pass patch path patient patrol pattern pause pave \
        payment peace peanut pear peasant pelican pen penalty pencil people pepper perfect permit person pet phone photo phrase \
        physical piano picnic picture piece pig pigeon pill pilot pink pioneer pipe pistol pitch pizza place planet plastic \
        plate play please pledge pluck plug plunge poem poet point polar pole police pond pony pool popular portion position \
        possible poster potato pottery poverty powder power practice praise predict prefer prepare present pretty prevent price \
        pride primary print priority prison private prize problem process produce profit program project promote proof property \
        prosper protect proud provide public pudding pull pulp pulse pumpkin punch pupil puppy purchase purity purpose purse \
        push put puzzle pyramid quality quantum quarter question quick quit quiz quote rabbit raccoon race rack radar radio \
        rail rain raise rally ramp ranch random range rapid rare rate rather raven raw razor ready real reason rebel rebuild \
        recall receive recipe record recycle reduce reflect reform refuse region regret regular reject relax release relief \
        rely remain remember remind remove render renew rent reopen repair repeat replace report require rescue resemble \
        resist resource response result retire retreat return reunion reveal review reward rhythm rib ribbon rice rich ride \
        ridge rifle right rigid ring riot ripple risk ritual rival river road roast robot robust rocket romance roof rookie \
        room rose rotate rough round route royal rubber rude rug rule run runway rural sad saddle sadness safe sail salad \
        salmon salon salt salute same sample sand satisfy satoshi sauce sausage save say scale scan scare scatter scene \
        scheme school science scissors scorpion scout scrap screen script scrub sea search season seat second secret section \
        security seed seek segment select sell seminar senior sense sentence series service session settle setup seven shadow \
        shaft shallow share shed shell sheriff shield shift shine ship shiver shock shoe shoot shop short shoulder shove shrimp \
        shrug shuffle shy sibling sick side siege sight sign silent silk silly silver similar simple since sing siren sister \
        situate six size skate sketch ski skill skin skirt skull slab slam sleep slender slice slide slight slim slogan slot \
        slow slush small smart smile smoke smooth snack snake snap sniff snow soap soccer social sock soda soft solar soldier \
        solid solution solve someone song soon sorry sort soul sound soup source south space spare spatial spawn speak special \
        speed spell spend sphere spice spider spike spin spirit split spoil sponsor spoon sport spot spray spread spring spy \
        square squeeze squirrel stable stadium staff stage stairs stamp stand start state stay steak steel stem step stereo \
        stick still sting stock stomach stone stool story stove strategy street strike strong struggle student stuff stumble \
        style subject submit subway success such sudden suffer sugar suggest suit summer sun sunny sunset super supply supreme \
        sure surface surge surprise surround survey suspect sustain swallow swamp swap swarm swear sweet swift swim swing \
        switch sword symbol symptom syrup system table tackle tag tail talent talk tank tape target task taste tattoo taxi \
        teach team tell ten tenant tennis tent term test text thank that theme then theory there they thing this thought three \
        thrive throw thumb thunder ticket tide tiger tilt timber time tiny tip tired tissue title toast tobacco today toddler \
        toe together toilet token tomato tomorrow tone tongue tonight tool tooth top topic topple torch tornado tortoise toss \
        total tourist toward tower town toy track trade traffic tragic train transfer trap trash travel tray treat tree trend \
        trial tribe trick trigger trim trip trophy trouble truck true truly trumpet trust truth try tube tuition tumble tuna \
        tunnel turkey turn turtle twelve twenty twice twin twist two type typical ugly umbrella unable unaware uncle uncover \
        under undo unfair unfold unhappy uniform unique unit universe unknown unlock until unusual unveil update upgrade uphold \
        upon upper upset urban urge usage use used useful useless usual utility vacant vacuum vague valid valley valve van \
        vanish vapor various vast vault vehicle velvet vendor venture venue verb verify version very vessel veteran viable \
        vibrant vicious victory video view village vintage violin virtual virus visa visit visual vital vivid vocal voice void \
        volcano volume vote voyage wage wagon wait walk wall walnut want warfare warm warrior wash wasp waste water wave way \
        wealth weapon wear weasel weather web wedding weekend weird welcome west wet whale what wheat wheel when where whip \
        whisper wide width wife wild will win window wine wing wink winner winter wire wisdom wise wish witness wolf woman \
        wonder wood wool word work world worry worth wrap wreck wrestle wrist write wrong yard year yellow you young youth zebra zero zoo
        """
        return Set(raw.split(separator: " ").map(String.init))
    }()
}
