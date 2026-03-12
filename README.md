# Dusk for Plex

A native Swift/SwiftUI Plex client for Apple platforms.

## Features

- [x] Direct Play
- [x] Plex authentication & server discovery
- [x] Library browsing
- [x] Search
- [x] Movie & TV show detail views
- [ ] Subtitle & audio track selection
- [ ] Continuous Playback
- [ ] App Store Release
- [ ] tvOS App
- [ ] Skip Intro & Credits
- [ ] Passout Protection (Are you still watching?)
- [ ] macOS App
- [ ] Transcoding Support
- [ ] Offline playback (Downloads)
- [ ] Plex Home Integration

## Setup

```bash
# 1. Download MobileVLCKit into Frameworks/
mkdir -p Frameworks && cd Frameworks
curl -L -o MobileVLCKit.tar.xz "https://download.videolan.org/pub/cocoapods/prod/MobileVLCKit-3.7.2-3e42ae47-79128878.tar.xz"
tar xf MobileVLCKit.tar.xz && rm MobileVLCKit.tar.xz
mv MobileVLCKit-binary/MobileVLCKit.xcframework .
mv MobileVLCKit-binary/COPYING.txt VLCKit-LICENSE.txt
rm -rf MobileVLCKit-binary
cd ..

# 2. Open in Xcode
open Dusk.xcodeproj
```

## License

MIT
