# TCPDF vendor pin

- Upstream: `https://github.com/tecnickcom/TCPDF`
- Version: `6.11.3`
- Source archive: `https://github.com/tecnickcom/TCPDF/archive/refs/tags/6.11.3.zip`
- Source archive SHA-256: `65F9AB071D0BFC4D3796C399A7D43A6F2E4F982D50C15D204B0B5FEDCA36504E`
- License: LGPL-3.0-or-later (upstream `LICENSE.TXT` is retained)

The repository contains the runtime distribution without upstream examples,
tests, development scripts or GitHub metadata. CEH uses only direct PDF cells,
bundled DejaVu fonts, local PNG images and in-memory PDF output.

CEH patch: cURL option constants are initialized lazily inside TCPDF's optional
remote-resource functions. This avoids requiring ext-curl merely to construct a
local-only document. Remote URL support still uses cURL when explicitly called.
