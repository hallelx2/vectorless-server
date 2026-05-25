# vectorless-server — moved

⚠️ **This repository has been merged into [`vectorless-engine`](https://github.com/hallelx2/vectorless-engine).**

The transport server now lives there as `cmd/server`, alongside the engine
library and `cmd/engine`. There are no longer separate modules to clone or
keep in sync.

To build the server:

```bash
git clone https://github.com/hallelx2/vectorless-engine
cd vectorless-engine
go build ./cmd/server          # or: docker build -f Dockerfile.server -t vectorless-server .
```

This repo is archived and kept only for history.
