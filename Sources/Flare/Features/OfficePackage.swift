import Foundation

/// 生成可被 Word / PowerPoint / Excel / Pages / Keynote / Numbers 打开的空白 OOXML 文件
enum OfficePackage {
    static func writeDOCX(to url: URL, title: String) throws {
        let now = isoNow()
        let bodyTitle = xmlEscape(title)
        let entries: [ZipEntry] = [
            ZipEntry(path: "[Content_Types].xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
              <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
              <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
              <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
            </Types>
            """),
            ZipEntry(path: "_rels/.rels", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
              <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
              <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
            </Relationships>
            """),
            ZipEntry(path: "word/_rels/document.xml.rels", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
            </Relationships>
            """),
            ZipEntry(path: "word/document.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:pPr><w:pStyle w:val="Title"/></w:pPr>
                  <w:r><w:t>\(bodyTitle)</w:t></w:r>
                </w:p>
                <w:p>
                  <w:r><w:t>创建于 \(xmlEscape(displayNow())) · \(xmlEscape(FlareBrand.name))</w:t></w:r>
                </w:p>
                <w:p><w:r><w:t></w:t></w:r></w:p>
                <w:sectPr>
                  <w:pgSz w:w="11906" w:h="16838"/>
                  <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """),
            ZipEntry(path: "word/styles.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
                <w:name w:val="Normal"/>
                <w:qFormat/>
              </w:style>
              <w:style w:type="paragraph" w:styleId="Title">
                <w:name w:val="Title"/>
                <w:basedOn w:val="Normal"/>
                <w:qFormat/>
                <w:rPr><w:b/><w:sz w:val="56"/></w:rPr>
              </w:style>
            </w:styles>
            """),
            ZipEntry(path: "docProps/core.xml", text: coreProps(title: title, created: now)),
            ZipEntry(path: "docProps/app.xml", text: appProps(application: "Microsoft Word", pages: 1))
        ]
        try SimpleZip.write(entries: entries, to: url)
    }

    static func writePPTX(to url: URL, title: String) throws {
        let now = isoNow()
        let slideTitle = xmlEscape(title)
        let entries: [ZipEntry] = [
            ZipEntry(path: "[Content_Types].xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
              <Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
              <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
              <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
              <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
              <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
              <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
            </Types>
            """),
            ZipEntry(path: "_rels/.rels", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
              <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
              <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
            </Relationships>
            """),
            ZipEntry(path: "ppt/_rels/presentation.xml.rels", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>
              <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
              <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
            </Relationships>
            """),
            ZipEntry(path: "ppt/presentation.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
              xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
              <p:sldMasterIdLst>
                <p:sldMasterId id="2147483648" r:id="rId1"/>
              </p:sldMasterIdLst>
              <p:sldIdLst>
                <p:sldId id="256" r:id="rId2"/>
              </p:sldIdLst>
              <p:sldSz cx="12192000" cy="6858000"/>
              <p:notesSz cx="6858000" cy="9144000"/>
            </p:presentation>
            """),
            ZipEntry(path: "ppt/slides/_rels/slide1.xml.rels", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
            </Relationships>
            """),
            ZipEntry(path: "ppt/slides/slide1.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
              xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
              <p:cSld>
                <p:spTree>
                  <p:nvGrpSpPr>
                    <p:cNvPr id="1" name=""/>
                    <p:cNvGrpSpPr/>
                    <p:nvPr/>
                  </p:nvGrpSpPr>
                  <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
                  <p:sp>
                    <p:nvSpPr>
                      <p:cNvPr id="2" name="Title"/>
                      <p:cNvSpPr txBox="1"><a:spLocks noGrp="1"/></p:cNvSpPr>
                      <p:nvPr><p:ph type="ctrTitle"/></p:nvPr>
                    </p:nvSpPr>
                    <p:spPr>
                      <a:xfrm><a:off x="685800" y="1825625"/><a:ext cx="10820400" cy="1143000"/></a:xfrm>
                    </p:spPr>
                    <p:txBody>
                      <a:bodyPr/><a:lstStyle/>
                      <a:p>
                        <a:r><a:rPr lang="zh-CN" sz="4400" b="1"/><a:t>\(slideTitle)</a:t></a:r>
                      </a:p>
                    </p:txBody>
                  </p:sp>
                  <p:sp>
                    <p:nvSpPr>
                      <p:cNvPr id="3" name="Subtitle"/>
                      <p:cNvSpPr txBox="1"><a:spLocks noGrp="1"/></p:cNvSpPr>
                      <p:nvPr><p:ph type="subTitle" idx="1"/></p:nvPr>
                    </p:nvSpPr>
                    <p:spPr>
                      <a:xfrm><a:off x="1371600" y="3429000"/><a:ext cx="9448800" cy="1143000"/></a:xfrm>
                    </p:spPr>
                    <p:txBody>
                      <a:bodyPr/><a:lstStyle/>
                      <a:p>
                        <a:r><a:rPr lang="zh-CN" sz="1800"/><a:t>创建于 \(xmlEscape(displayNow())) · \(xmlEscape(FlareBrand.name))</a:t></a:r>
                      </a:p>
                    </p:txBody>
                  </p:sp>
                </p:spTree>
              </p:cSld>
              <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
            </p:sld>
            """),
            ZipEntry(path: "ppt/slideLayouts/_rels/slideLayout1.xml.rels", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
            </Relationships>
            """),
            ZipEntry(path: "ppt/slideLayouts/slideLayout1.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
              xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="title" preserve="1">
              <p:cSld name="Title Slide">
                <p:spTree>
                  <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
                  <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
                  <p:sp>
                    <p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="ctrTitle"/></p:nvPr></p:nvSpPr>
                    <p:spPr/>
                    <p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t></a:t></a:r></a:p></p:txBody>
                  </p:sp>
                  <p:sp>
                    <p:nvSpPr><p:cNvPr id="3" name="Subtitle"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="subTitle" idx="1"/></p:nvPr></p:nvSpPr>
                    <p:spPr/>
                    <p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t></a:t></a:r></a:p></p:txBody>
                  </p:sp>
                </p:spTree>
              </p:cSld>
              <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
            </p:sldLayout>
            """),
            ZipEntry(path: "ppt/slideMasters/_rels/slideMaster1.xml.rels", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
              <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
            </Relationships>
            """),
            ZipEntry(path: "ppt/slideMasters/slideMaster1.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
              xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
              <p:cSld>
                <p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>
                <p:spTree>
                  <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
                  <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
                  <p:sp>
                    <p:nvSpPr><p:cNvPr id="2" name="Title Placeholder"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
                    <p:spPr><a:xfrm><a:off x="685800" y="1143000"/><a:ext cx="10820400" cy="1600200"/></a:xfrm></p:spPr>
                    <p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t></a:t></a:r></a:p></p:txBody>
                  </p:sp>
                </p:spTree>
              </p:cSld>
              <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
              <p:sldLayoutIdLst>
                <p:sldLayoutId id="2147483649" r:id="rId1"/>
              </p:sldLayoutIdLst>
            </p:sldMaster>
            """),
            ZipEntry(path: "ppt/theme/theme1.xml", text: themeXML()),
            ZipEntry(path: "docProps/core.xml", text: coreProps(title: title, created: now)),
            ZipEntry(path: "docProps/app.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
              xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
              <Application>\(xmlEscape(FlareBrand.name))</Application>
              <Slides>1</Slides>
              <PresentationFormat>Widescreen</PresentationFormat>
            </Properties>
            """)
        ]
        try SimpleZip.write(entries: entries, to: url)
    }

    static func writeXLSX(to url: URL, title: String) throws {
        let now = isoNow()
        let sheetName = "工作表1"
        let entries: [ZipEntry] = [
            ZipEntry(path: "[Content_Types].xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
              <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
              <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
              <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
              <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
              <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
            </Types>
            """),
            ZipEntry(path: "_rels/.rels", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
              <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
              <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
            </Relationships>
            """),
            ZipEntry(path: "xl/_rels/workbook.xml.rels", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
              <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
              <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
            </Relationships>
            """),
            ZipEntry(path: "xl/workbook.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <sheets>
                <sheet name="\(xmlEscape(sheetName))" sheetId="1" r:id="rId1"/>
              </sheets>
            </workbook>
            """),
            ZipEntry(path: "xl/worksheets/sheet1.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <sheetData>
                <row r="1">
                  <c r="A1" t="s"><v>0</v></c>
                  <c r="B1" t="s"><v>1</v></c>
                  <c r="C1" t="s"><v>2</v></c>
                </row>
                <row r="2">
                  <c r="A2" t="s"><v>3</v></c>
                </row>
              </sheetData>
            </worksheet>
            """),
            ZipEntry(path: "xl/sharedStrings.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="4" uniqueCount="4">
              <si><t>\(xmlEscape(title))</t></si>
              <si><t>列 B</t></si>
              <si><t>列 C</t></si>
              <si><t>创建于 \(xmlEscape(displayNow())) · \(xmlEscape(FlareBrand.name))</t></si>
            </sst>
            """),
            ZipEntry(path: "xl/styles.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
              <fonts count="1"><font><sz val="12"/><color theme="1"/><name val="Helvetica Neue"/><family val="2"/></font></fonts>
              <fills count="2">
                <fill><patternFill patternType="none"/></fill>
                <fill><patternFill patternType="gray125"/></fill>
              </fills>
              <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
              <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
              <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
            </styleSheet>
            """),
            ZipEntry(path: "docProps/core.xml", text: coreProps(title: title, created: now)),
            ZipEntry(path: "docProps/app.xml", text: """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
              <Application>\(xmlEscape(FlareBrand.name))</Application>
            </Properties>
            """)
        ]
        try SimpleZip.write(entries: entries, to: url)
    }

    // MARK: - Shared XML helpers

    private static func coreProps(title: String, created: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
          xmlns:dc="http://purl.org/dc/elements/1.1/"
          xmlns:dcterms="http://purl.org/dc/terms/"
          xmlns:dcmitype="http://purl.org/dc/dcmitype/"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(xmlEscape(title))</dc:title>
          <dc:creator>\(xmlEscape(FlareBrand.name))</dc:creator>
          <cp:lastModifiedBy>\(xmlEscape(FlareBrand.name))</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(created)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(created)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private static func appProps(application: String, pages: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
          <Application>\(xmlEscape(FlareBrand.name))</Application>
          <Pages>\(pages)</Pages>
        </Properties>
        """
    }

    private static func themeXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Flare Pro">
          <a:themeElements>
            <a:clrScheme name="Flare Pro">
              <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
              <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
              <a:dk2><a:srgbClr val="1A1A1A"/></a:dk2>
              <a:lt2><a:srgbClr val="F2F2F2"/></a:lt2>
              <a:accent1><a:srgbClr val="2F6FED"/></a:accent1>
              <a:accent2><a:srgbClr val="ED7D31"/></a:accent2>
              <a:accent3><a:srgbClr val="A5A5A5"/></a:accent3>
              <a:accent4><a:srgbClr val="FFC000"/></a:accent4>
              <a:accent5><a:srgbClr val="5B9BD5"/></a:accent5>
              <a:accent6><a:srgbClr val="70AD47"/></a:accent6>
              <a:hlink><a:srgbClr val="0563C1"/></a:hlink>
              <a:folHlink><a:srgbClr val="954F72"/></a:folHlink>
            </a:clrScheme>
            <a:fontScheme name="Flare Pro">
              <a:majorFont><a:latin typeface="Helvetica Neue"/><a:ea typeface="PingFang SC"/><a:cs typeface=""/></a:majorFont>
              <a:minorFont><a:latin typeface="Helvetica Neue"/><a:ea typeface="PingFang SC"/><a:cs typeface=""/></a:minorFont>
            </a:fontScheme>
            <a:fmtScheme name="Flare Pro">
              <a:fillStyleLst>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
              </a:fillStyleLst>
              <a:lnStyleLst>
                <a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
                <a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
                <a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
              </a:lnStyleLst>
              <a:effectStyleLst>
                <a:effectStyle><a:effectLst/></a:effectStyle>
                <a:effectStyle><a:effectLst/></a:effectStyle>
                <a:effectStyle><a:effectLst/></a:effectStyle>
              </a:effectStyleLst>
              <a:bgFillStyleLst>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
                <a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
              </a:bgFillStyleLst>
            </a:fmtScheme>
          </a:themeElements>
        </a:theme>
        """
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    private static func displayNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Minimal ZIP (store)

struct ZipEntry {
    let path: String
    let data: Data

    init(path: String, data: Data) {
        self.path = path
        self.data = data
    }

    init(path: String, text: String) {
        self.path = path
        self.data = Data(text.utf8)
    }
}

enum SimpleZip {
    static func write(entries: [ZipEntry], to url: URL) throws {
        var bytes = Data()
        var central = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let nameLen = UInt16(nameData.count)
            let size = UInt32(entry.data.count)
            let crc = crc32(entry.data)
            let localOffset = offset

            var local = Data()
            local.append(u32(0x04034b50))
            local.append(u16(20)) // version needed
            local.append(u16(0))  // flags
            local.append(u16(0))  // store
            local.append(u16(0))  // time
            local.append(u16(0))  // date
            local.append(u32(crc))
            local.append(u32(size))
            local.append(u32(size))
            local.append(u16(nameLen))
            local.append(u16(0)) // extra
            local.append(nameData)
            local.append(entry.data)
            bytes.append(local)
            offset += UInt32(local.count)

            var cen = Data()
            cen.append(u32(0x02014b50))
            cen.append(u16(20))
            cen.append(u16(20))
            cen.append(u16(0))
            cen.append(u16(0))
            cen.append(u16(0))
            cen.append(u16(0))
            cen.append(u32(crc))
            cen.append(u32(size))
            cen.append(u32(size))
            cen.append(u16(nameLen))
            cen.append(u16(0))
            cen.append(u16(0))
            cen.append(u16(0))
            cen.append(u16(0))
            cen.append(u32(0))
            cen.append(u32(localOffset))
            cen.append(nameData)
            central.append(cen)
        }

        let centralOffset = offset
        let centralSize = UInt32(central.count)
        bytes.append(central)

        var end = Data()
        end.append(u32(0x06054b50))
        end.append(u16(0))
        end.append(u16(0))
        end.append(u16(UInt16(entries.count)))
        end.append(u16(UInt16(entries.count)))
        end.append(u32(centralSize))
        end.append(u32(centralOffset))
        end.append(u16(0))
        bytes.append(end)

        try bytes.write(to: url, options: .atomic)
    }

    private static func u16(_ v: UInt16) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 2)
    }

    private static func u32(_ v: UInt32) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 4)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xff)
            crc = (crc >> 8) ^ crcTable[idx]
        }
        return crc ^ 0xffff_ffff
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()
}
