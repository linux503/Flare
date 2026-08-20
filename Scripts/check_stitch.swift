import AppKit
let url = URL(fileURLWithPath:"/Users/a503/Downloads/Mac-soft/Flare/.build-stitch-test/stitched.png")
let rep = NSBitmapImageRep(data: NSImage(contentsOf:url)!.tiffRepresentation!)!
func isChrome(_ y:Int)->Bool {
  var hit=0,n=0
  for x in stride(from:0,to:rep.pixelsWide,by:2){
    let c=rep.colorAt(x:x,y:y)!; n+=1
    if abs(c.redComponent*255-220)<30 && abs(c.greenComponent*255-36)<30 && abs(c.blueComponent*255-36)<30 { hit+=1 }
  }
  return Double(hit)/Double(n) > 0.72
}
var bands=0; var inB=false; var len=0
for y in 0..<rep.pixelsHigh {
  if isChrome(y) { len+=1; inB=true }
  else if inB { if len>10 { bands+=1; print("band end y=\(y) len=\(len)") }; inB=false; len=0 }
}
if inB && len>10 { bands+=1; print("band end EOF len=\(len)") }
print("bands", bands, "height", rep.pixelsHigh)
