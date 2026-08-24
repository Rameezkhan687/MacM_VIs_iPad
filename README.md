# MoleculePad

MoleculePad is a clean-room, touch-first molecular visualization workspace for iPad. It is inspired by established desktop molecular-graphics workflows but does not contain UCSF ChimeraX source code, artwork, or branding.

## Working in this first build

- Native iPadOS 17 SwiftUI interface with a SceneKit 3D viewport
- PDB files from the Files app (`.pdb`, `.ent`)
- Direct PDB downloads from RCSB using four-character IDs
- Direct primary-map downloads from EMDB using `EMD-` accession IDs
- MRC/CCP4 density maps (`.mrc`, `.map`, `.ccp4`, and gzip-compressed variants), including modes 0, 1, 2, and 6
- Interactive density isosurfaces with contour, color, opacity, and wireframe controls
- Ball-and-stick, spacefill, sticks, backbone, and cartoon representations
- Cartoon helices, beta-sheet arrows, and smooth coil traces from PDB secondary-structure records
- Element, chain, residue, and monochrome coloring
- Touch rotation, pan, zoom, atom picking, and two-atom distance measurements
- Group selection by chain, residue number/name, element, atom name, ligand, water, or the full model
- Distance, three-atom angle, and four-atom torsion measurements
- A plain-language Copilot that translates multi-step requests into safe, allow-listed commands
- A compact expert terminal (`help` lists the implemented commands)
- Pure-Swift tests for PDB parsing, bond inference, and MRC parsing

Copilot examples include “Download 1CRN and show it as a cartoon,” “Color every chain differently,” and “Hide the map and clear my selection.” This first layer works locally without an account. A future open-ended AI provider must be routed through a secure backend; API keys must never be embedded in the iPad app or committed to this public repository.

The staged ChimeraX-capability roadmap is tracked in [`FEATURE_PARITY.md`](FEATURE_PARITY.md). Copilot, Terminal, and touch interfaces share the same underlying operations so new modules automatically become available to each interface.

## Run on an iPad

1. Install the current Xcode from the Mac App Store.
2. Open `MoleculePad.xcodeproj`.
3. Select the MoleculePad target, open **Signing & Capabilities**, and choose your Apple Developer team.
4. Connect the iPad by USB or enable wireless debugging, select it as the run destination, and press Run.

A free Apple ID can install a development build on your own iPad. TestFlight or App Store distribution requires enrollment in the Apple Developer Program.

## Test the file-format engine

From this directory, run:

```sh
swift test
```

## Scope and roadmap

This is a functional foundation, not feature parity with the decades-old desktop ChimeraX codebase. High-value next layers are mmCIF, segmented map regions, molecular surfaces, symmetry, fitting, session files, image/movie export, DICOM, and an extensible analysis-command engine. A literal ChimeraX port or redistributed derivative requires prior written permission from UCSF under its published license.

## Attribution

Protein Data Bank downloads are provided by [RCSB PDB](https://www.rcsb.org/). Electron-density maps are provided by the [EMDB archive at EMBL-EBI](https://www.ebi.ac.uk/emdb/). “UCSF ChimeraX” is associated with the Regents of the University of California; this project is independent and is not endorsed by UCSF.
