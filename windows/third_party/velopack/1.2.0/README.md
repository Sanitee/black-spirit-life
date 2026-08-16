# Velopack C/C++ runtime 1.2.0

This directory contains the Windows x64 dynamic C API from the official
`velopack_libc_1.2.0.zip` release archive.

- Upstream: <https://github.com/velopack/velopack/releases/tag/1.2.0>
- Archive SHA-256:
  `547262ED7A1AB1FF62F580AA53851EDE2F1A451AC61B8974EB7BC01117488835`
- `include/Velopack.h` SHA-256:
  `E6711FCC565386EF6C4E80079C44B6F3221A98E5C43B33A9331311A28B54C8FC`
- `include/Velopack.hpp` SHA-256:
  `16CFDF96C48360B7D76BA06DD941D464E3427FA7ACA2F84626C6EE3AF76B14C9`
- `lib/x64/velopack_libc_win_x64_msvc.dll` SHA-256:
  `C36D8B984639A8AF9D3397088D3FFB8213FE1BD0917F555CF0C6E33F014403EC`
- `lib/x64/velopack_libc_win_x64_msvc.dll.lib` SHA-256:
  `063DEF3F77CCDD44FD719536B9CB464015CC34E3C10197ADD6643AEC02408D11`

Only the files required by the Windows x64 runner are vendored. The
matching `vpk` 1.2.0 tool is invoked locally through .NET when packaging; it
is not installed globally and no release is uploaded by the local workflow.
