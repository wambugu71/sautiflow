# Android native curl artifacts

Place prebuilt Android curl artifacts here for native URL streaming support.

Recommended (static) layout:

- include/ (curl headers)
- armeabi-v7a/libcurl.a
- arm64-v8a/libcurl.a

Optional emulator/server ABIs (if you enable them in Gradle):

- x86/libcurl.a
- x86_64/libcurl.a

If your static `libcurl.a` requires additional libraries, pass them via Gradle property:

- `MINIAUDIODART_CURL_EXTRA_LIBS=ssl;crypto;z`

and ensure matching prebuilt artifacts exist for each enabled ABI.
