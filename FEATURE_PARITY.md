# MoleculePad Feature-Parity Audit

This audit maps the public UCSF ChimeraX User Guide into original MoleculePad modules. It records functional workflow coverage, not a source-code port. Copilot is the top-level interface and invokes the same typed operations as Terminal and touch controls.

Source catalog: <https://www.cgl.ucsf.edu/chimerax/docs/user/index.html>

## Molecular data and rendering

- [x] Native iPad viewport with touch/pencil input, picking, selection, measurements, and presentation mode
- [x] PDB, mmCIF, SDF/MOL, MOL2, multi-frame XYZ, multi-model PDB, and binary DCD import
- [x] mmCIF biological assemblies/operator expressions, asymmetric units, and PDB/mmCIF alternate locations
- [x] Ball-and-stick, sticks, spacefill, backbone, cartoon, nucleotide, glycan, and thermal-ellipsoid styles
- [x] Secondary-structure helices, sheet arrows, coils, labels, axes, scale bars, lighting, clipping, and saved directions/scenes
- [x] Solvent-accessible solid/mesh/dot surfaces with probe, opacity, and uniform/property per-vertex coloring
- [x] Hydrogen-bond/contact/clash pseudobonds plus user-created pseudobond groups
- [x] Selection-linked 3D arrows and freeform Apple Pencil/touch 2D annotation canvas

## Maps and medical imaging

- [x] MRC/CCP4/gzip maps, isosurfaces, volume point clouds, and orthogonal slices
- [x] Smoothing, sharpening, crop, atom zone, statistics, difference maps, and connected-density segmentation
- [x] Atom-to-map and map-to-map translational fitting
- [x] Coarse-to-fine rotational plus translational rigid atom-to-map fitting
- [x] NIfTI, NRRD, uncompressed DICOM, filename-ordered DICOM series, and local clinical metadata browser
- [ ] Compressed DICOM pixel transfer syntaxes — detected but intentionally require an external licensed codec or conversion

## Analysis and comparison

- [x] Hydrogen bonds, contacts, clashes, cavities, chain interfaces, area/volume estimates, centroids, axes, and fitted planes
- [x] Sequence extraction, pairwise alignment, consensus/conservation, coordinate Matchmaker, and fitted RMSD
- [x] NCBI protein BLAST and official RCSB global 3D-similarity search with ranked results
- [x] AlphaFold DB model import
- [x] Foldseek, ESMFold, OpenFold, and Boltz typed compute-provider integration over authenticated HTTPS

## Editing and modeling

- [x] Build/delete atoms, add/delete bonds, mutate residue names, rename chains, and undo/redo
- [x] Side-chain rotamers, hydrogen addition, simple charges, Dock Prep, bond relaxation, torsions, and vector tugging
- [x] Ligand docking-pose contact/clash analysis
- [x] Numbered-gap backbone loop modeling and aligned-reference comparative atom completion

## Sessions, automation, and sharing

- [x] Versioned sessions with structures, maps, selections, aliases, scenes, appearance, plug-ins, custom pseudobonds, and annotations
- [x] PNG, H.264 MP4 trajectory, PDB coordinate, and SceneKit 3D-scene export
- [x] Command scripts, semicolon batches, reusable aliases, custom quick buttons, and multi-file batch processing UI
- [x] App-Store-safe declarative iPad plug-in manifests and an in-app task manager
- [x] On-device Copilot and optional secure server-backed open-ended Copilot with strict structured output and double allow-list validation
- [x] Full-screen presentation and portable session handoff workflows
- [ ] Real-time multi-user and spatial/VR workflows — require external cloud/SharePlay coordination or a separate visionOS target and entitlements

## Explicit compatibility boundaries

These items cannot honestly be delivered as self-contained iPad code in this public repository without third-party licensing, credentials, infrastructure, or a different Apple platform target:

- XTC and other proprietary/compressed MD decoders beyond included DCD support
- JPEG/JPEG-LS/JPEG 2000/RLE DICOM codecs
- Hosted Foldseek/model-inference GPU capacity (the secure provider protocol and UI are included)
- Live collaboration infrastructure and visionOS immersive rendering

All other roadmap rows above are implemented in the repository and covered by either automated core tests, full iPad source typechecking, or the Xcode build validation described in the README.
