# MoleculePad Feature-Parity Roadmap

This roadmap groups the public UCSF ChimeraX User Guide into original, reusable MoleculePad modules. It is a capability target, not a source-code port. Copilot remains the top-level interface and invokes the same typed operations as Terminal and touch controls.

Source catalog: <https://www.cgl.ucsf.edu/chimerax/docs/user/index.html>

## Implemented foundation

- [x] Native iPad viewport and touch navigation
- [x] PDB and EMDB fetching
- [x] PDB, MRC, CCP4, and compressed-map import
- [x] Atom, stick, ball-and-stick, space-filling, backbone, and cartoon display
- [x] Density-map isosurfaces and contour controls
- [x] Atom and group selection by chain, residue, element, atom name, ligand, and water
- [x] Distance, angle, and torsion measurements
- [x] Terminal plus allow-listed plain-language Copilot

## Molecular data and rendering

- [ ] mmCIF and biological assemblies
- [ ] Alternate locations, multiple coordinate sets, and trajectories
- [ ] Molecular surfaces with solid, mesh, and dot styles
- [ ] Nucleotide, glycan, thermal-ellipsoid, and pseudobond representations
- [ ] Labels, arrows, scale bars, clipping, lighting presets, and saved views

## Maps and imaging

- [ ] Solid-volume rendering and orthogonal slices
- [ ] Map filtering, cropping, zoning, statistics, and difference maps
- [ ] Atom-to-map and map-to-map fitting
- [ ] Segmentation and region measurement
- [ ] DICOM, NIfTI, and NRRD medical-image workflows

## Analysis and comparison

- [ ] Hydrogen bonds, contacts, clashes, cavities, and interfaces
- [ ] Surface area, volume, RMSD, axes, planes, and centroids
- [ ] Sequence viewer, alignments, conservation, and Matchmaker
- [ ] BLAST, Foldseek, and similar-structure analysis
- [ ] AlphaFold, ESMFold, OpenFold, and Boltz integrations

## Editing and simulation

- [ ] Build and modify atoms, bonds, residues, and chains
- [ ] Rotamers, mutation, hydrogens, charges, and Dock Prep
- [ ] Minimization, torsion editing, and interactive tugging
- [ ] Ligand docking-result analysis and comparative/loop modeling

## Sessions, automation, and sharing

- [ ] Undo/redo operation history
- [ ] Session save/restore, scenes, images, movies, and 3D export
- [ ] Command scripts, aliases, custom button panels, and batch processing
- [ ] iPad plugin API and task manager
- [ ] Secure server-backed open-ended Copilot with typed function calls
- [ ] Collaboration, presentation, and spatial/VR workflows
