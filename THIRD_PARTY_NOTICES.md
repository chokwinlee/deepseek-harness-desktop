# Third-party notices

## DeepSeek Harness

This application launches and redistributes the npm package [`@deepseek-ai/dsh`](https://www.npmjs.com/package/@deepseek-ai/dsh), developed by [DeepSeek AI](https://github.com/deepseek-ai/deepseek-harness).

MIT License

Copyright (c) 2026 DeepSeek

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

The packaged application also contains transitive dependencies of DeepSeek Harness and Electron. Their license metadata is available in the installed npm package tree and generated application resources.

## Android Remote dependencies

The Android client uses the following third-party components:

- AndroidX, Jetpack Compose, Material 3, Navigation, Lifecycle, CameraX,
  ExifInterface, and Android test libraries, licensed under the
  [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
- Kotlin, Kotlin Coroutines, and Kotlin Serialization, licensed under the
  [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
- [OkHttp and Okio](https://square.github.io/okhttp/), licensed under the
  [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
- The bundled [ML Kit barcode-scanning SDK](https://developers.google.com/ml-kit/vision/barcode-scanning/android),
  used only for on-device QR pairing. Its use is governed by the applicable
  Google APIs and Android SDK terms.

The Compose Preview Screenshot Testing plugin is a build-time verification
tool and is not packaged as an application runtime service.
