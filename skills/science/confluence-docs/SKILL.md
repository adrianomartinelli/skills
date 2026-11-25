---
name: confluence-docs
description: Read and write pages on the Bentires-Alj group wiki (Confluence at wiki.biozentrum.unibas.ch) through its REST API. Use when the user links a wiki.biozentrum.unibas.ch page, or asks to put, update, or read content on the group wiki.
---

# Confluence docs

- Wiki: https://wiki.biozentrum.unibas.ch (self-hosted Confluence; the Atlassian connector does not reach it)
- Group space: `DBMRGBM01` (Group Bentires-Alj Home → Lab Books)
- API: `https://wiki.biozentrum.unibas.ch/rest/api/content`
- Token: `CONFLUENCE_TOKEN` in `$HOME/.env`. Send it as `Authorization: Bearer <token>`. Never print it.

```bash
T=$(grep -E '^\s*(export\s+)?CONFLUENCE_TOKEN=' ~/.env | tail -1 | sed -E 's/^\s*(export\s+)?CONFLUENCE_TOKEN=//; s/^["'\'']//; s/["'\'']\s*$//')
curl -s -H "Authorization: Bearer $T" "https://wiki.biozentrum.unibas.ch/rest/api/content/<id>?expand=body.storage,version"
```

- Read a page before you change it. A PUT replaces the whole body and needs `version.number` + 1.
- Write the body in storage format (XHTML). Convert Markdown with `pixi exec --spec pandoc pandoc -f gfm -t html`.
- Add new pages as children (`"ancestors": [{"id": "<parent>"}]`). Do not edit other people's pages without asking.
