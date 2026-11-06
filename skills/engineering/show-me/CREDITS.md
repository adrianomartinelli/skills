# Credits

This skill is adapted from [Dex Horthy](https://github.com/dexhorthy)'s [`show-me`](https://github.com/humanlayer/skills/blob/main/plugins/show-me/skills/show-me/SKILL.md) skill in `humanlayer/skills` (MIT). The visual menu (pseudocode, call trees, file trees, Mermaid, diffs, whole blocks) and the placement guidance ("place each visual next to the short text it supports", "pick the smallest view") come from upstream. The adaptation aims the skill at explaining an existing component: the contract (what it consumes and produces), real config and artifact examples, the interaction flow, and edge cases, rendered as an interactive page. The upstream UI-oriented examples (component trees, UI diffs) are replaced with the contract view.

- Source: https://github.com/humanlayer/skills/blob/bba9d13ab34f0a87f1cc33df4dd196372393ddfc/plugins/show-me/skills/show-me/SKILL.md
- Commit: `bba9d13ab34f0a87f1cc33df4dd196372393ddfc` (2026-09-12, "Make show-me user-invocable"), the latest commit touching this file as of 2026-11-06
- SHA-256 of the upstream file at that commit: `434a2346cc95e313b0d367d477dda2e23ba642dd2181757415a09500664af100`

Check for upstream changes since the pinned commit:

```bash
gh api 'repos/humanlayer/skills/commits?path=plugins/show-me/skills/show-me/SKILL.md&per_page=5' --jq '.[] | "\(.sha[:12]) \(.commit.committer.date) \(.commit.message | split("\n")[0])"'
```

## License

```
MIT License

Copyright (c) 2026 HumanLayer

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
