# MoleculePad

MoleculePad is a clean-room, touch-first molecular visualization and analysis workspace for iPadOS 17. It recreates the major scientific workflows cataloged in the public UCSF ChimeraX User Guide with original Swift/SceneKit code; it does not contain ChimeraX source code, artwork, branding, or proprietary modules.

## Included in version 1.0

- PDB, mmCIF, SDF/MOL, MOL2, XYZ, DCD, MRC/CCP4, NIfTI, NRRD, DICOM, gzip map, command-script, plug-in-manifest, and MoleculePad session files
- Direct RCSB PDB, EMDB, and AlphaFold DB import; NCBI protein BLAST and official RCSB 3D-similarity search
- Biological assemblies, alternate locations, multiple coordinate sets, trajectory playback, and DCD trajectories using an open topology
- Ball-and-stick, sticks, spacefill, backbone, cartoon, nucleotide, glycan, and B-factor ellipsoid rendering
- Solvent-accessible surfaces in solid, mesh, and dot modes, including per-vertex element, chain, residue, B-factor, and charge coloring
- Isosurfaces, volume clouds, orthogonal slices, map filtering, crop/zone/difference operations, segmentation, and translational or rotational fitting
- Selection, measurements, labels, lighting, clipping, saved views/scenes, 3D arrows, custom pseudobonds, and Apple Pencil/touch 2D annotations
- Hydrogen bonds, contacts, clashes, cavities, interfaces, molecular geometry, sequence alignment/conservation, RMSD, and structural superposition
- Atom/bond editing, mutation, hydrogen/charge preparation, Dock Prep, minimization, torsion/rotamer editing, tugging, docking-pose analysis, loop building, and reference-template completion
- Undo/redo, versioned sessions, scripts, aliases, custom buttons, safe declarative plug-ins, multi-file batch processing, task history, and presentation mode
- PNG, MP4 trajectory, PDB coordinate, versioned session, and SceneKit 3D-scene export
- On-device plain-language Copilot plus an optional secure server Copilot; Foldseek, ESMFold, OpenFold, and Boltz use a configurable HTTPS compute provider

Copilot is the top-level interface. A request such as “download 1CRN, show a chain-colored cartoon, find hydrogen bonds, and start presentation mode” becomes a visible sequence of allow-listed MoleculePad commands. Terminal and touch controls call the same operations.

## Privacy and security

MoleculePad asks only for files explicitly selected with Apple’s document picker. It does not request access to Photos, Music, or Videos. Local structures, maps, sessions, and annotations stay on the device unless the user exports or sends them to a configured service.

Optional service URLs are stored in app preferences. Their access tokens are stored in the iPad Keychain. OpenAI or compute-provider keys belong on the server and must never be embedded in the app or committed to this public repository. The optional worker in [`Server/`](Server/) validates commands server-side; the iPad validates them again before execution.

## Run on an iPad

1. Install the current Xcode on a Mac and open `MoleculePad.xcodeproj`.
2. Select the MoleculePad target, open **Signing & Capabilities**, and choose your Apple Developer team.
3. Connect the iPad by USB or enable wireless debugging, select it as the run destination, and press Run.

A free Apple ID can install a development build on your own iPad. TestFlight or App Store distribution requires Apple Developer Program enrollment.

## Validate

```sh
swift test
xcodebuild -project MoleculePad.xcodeproj -scheme MoleculePad -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The core suite covers file formats, assemblies, surfaces, selections, analysis, map processing/fitting, editing/modeling, sessions, plug-ins, and backend validation. See [`FEATURE_PARITY.md`](FEATURE_PARITY.md) for the audit and [`Docs/EXTENSION_PROTOCOLS.md`](Docs/EXTENSION_PROTOCOLS.md) for server and plug-in contracts.

## Deliberate boundaries

- DCD is the included binary trajectory reader; proprietary or heavily compressed MD formats such as XTC require a separately licensed decoder.
- DICOM metadata and uncompressed pixel data are supported. JPEG/JPEG-LS/JPEG 2000/RLE and deflated transfer syntaxes are detected and rejected with a clear conversion message because no licensed medical codec is bundled.
- Foldseek and prediction models require user-selected compute infrastructure. The public repository contains the typed client protocol but no third-party credentials or paid GPU service.
- Presentation and portable session handoff work on iPad. Real-time multi-user synchronization and immersive spatial/VR rendering require separate cloud, SharePlay, or visionOS entitlements and are not falsely represented as local iPad features.
- Molecular modeling and minimization are interactive approximations for exploration, not replacements for validated force-field, clinical, or production modeling pipelines.

## Attribution

Data downloads are provided by [RCSB PDB](https://www.rcsb.org/), [EMDB at EMBL-EBI](https://www.ebi.ac.uk/emdb/), [AlphaFold DB](https://alphafold.ebi.ac.uk/), and [NCBI BLAST](https://blast.ncbi.nlm.nih.gov/). “UCSF ChimeraX” is associated with the Regents of the University of California. MoleculePad is independent and is not endorsed by UCSF.
