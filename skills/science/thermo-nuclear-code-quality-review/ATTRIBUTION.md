# Attribution

`SKILL.md` in this directory is a verbatim copy of an upstream file. It is kept byte-identical so
upstream changes can be diffed and merged; local adaptations, if any, are separate commits.

- Source: https://github.com/cursor/plugins/blob/6e3d2ea56d7d446b955eaae6ac4c8eef8bf504cf/cursor-team-kit/skills/thermo-nuclear-code-quality-review/SKILL.md
- Repository: `cursor/plugins`
- Path: `cursor-team-kit/skills/thermo-nuclear-code-quality-review/SKILL.md`
- Commit: `6e3d2ea56d7d446b955eaae6ac4c8eef8bf504cf` (2026-05-28, "Restore thermo-nuclear-code-quality-review in cursor-team-kit (#95)"), the latest commit touching this file as of 2026-10-23
- SHA-256 of the copied file: `7faca08b51b643b2ddd0836f92af15574444024685dcc1e677dbbb39ae8c9e8f`

Check for upstream changes since the pinned commit:

```bash
gh api 'repos/cursor/plugins/commits?path=cursor-team-kit/skills/thermo-nuclear-code-quality-review/SKILL.md&per_page=5' --jq '.[] | "\(.sha[:12]) \(.commit.committer.date) \(.commit.message | split("\n")[0])"'
```

## License

The upstream file is distributed under the following license
(`cursor-team-kit/LICENSE` at the same commit):

```
MIT License

Copyright (c) 2026 Cursor

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
