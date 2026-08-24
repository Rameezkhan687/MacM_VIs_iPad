# MoleculePad extension protocols

## Declarative `.molplugin` files

MoleculePad plug-ins are JSON manifests. They add buttons that run built-in allow-listed commands; they never load executable code.

```json
{
  "id": "org.example.presentation",
  "name": "Presentation Tools",
  "version": "1.0.0",
  "author": "Example Lab",
  "commands": [
    {
      "id": "clean-ribbon",
      "title": "Clean Ribbon",
      "symbol": "sparkles",
      "script": "style cartoon; color chain; label none; presentation start"
    }
  ]
}
```

Save the JSON with a `.molplugin` extension and open it with MoleculePad. The app limits manifest size, command count, command length, identifiers, and every script statement.

## Copilot endpoint

`POST` the following JSON to the configured endpoint:

```json
{
  "request": "show chain A as a cartoon and find hydrogen bonds",
  "context": {
    "structureName": "1CRN",
    "atomCount": 327,
    "chainIDs": ["A"],
    "mapName": null,
    "selectedAtomCount": 0
  },
  "supportedProtocolVersion": 1
}
```

Return:

```json
{
  "summary": "I’ll select chain A, use cartoon representation, and find hydrogen bonds.",
  "commands": ["select chain A", "style cartoon", "hbonds"]
}
```

Use HTTPS and optionally require a bearer token. MoleculePad stores that access token in Keychain and validates every returned command. A deployable reference worker is in [`../Server/`](../Server/).

## Molecular compute endpoint

MoleculePad sends one of four operations to the configured authenticated HTTPS endpoint:

```json
{
  "operation": "esmfold",
  "sequence": "MKT...",
  "pdb": null,
  "protocolVersion": 1
}
```

`operation` is `foldseek`, `esmfold`, `openfold`, or `boltz`. Prediction requests contain a protein sequence. Foldseek contains PDB text instead. Return:

```json
{
  "summary": "Prediction complete",
  "resultText": "Optional report or ranked matches",
  "structureURL": "https://results.example/model.cif"
}
```

`structureURL` is optional. When present it must use HTTPS (localhost HTTP is allowed for development), return at most 200 MB, and contain PDB or mmCIF coordinates. Provider API keys and GPU credentials remain on the server.
