# NVIDIA SimReady trial assets

Three source models replace existing shipping-scene objects in the trial branch. The app's
cube menu switches between the original kit and NVIDIA models. No source downloads or Blender
installation are needed to run the bundled app. The original kit is retained for comparison.

## Reproduce

From the repository root, with Python 3 and Blender 5.2.2:

```sh
python3 -m venv tmp/simready-trial/venv
tmp/simready-trial/venv/bin/pip install usd-core numpy pillow
python3 ios/tools/simready_trial/download.py
tmp/simready-trial/venv/bin/python ios/tools/simready_trial/convert.py
blender -b --factory-startup --python ios/tools/simready_trial/simplify.py
python3 ios/tools/simready_trial/manifest.py
```

Downloads are pinned to NVIDIA dataset revision
`524747d9b5e1f21b5b18b56041788c01d745f1a1` and stay under ignored `tmp/`.
Only the three selected source folders are downloaded. The per-file download manifest records
SHA-256 hashes. The application receives portable USD, resized texture atlases and licenses in
`ios/Salini/InsightAssets/SimReady/`; `checksums.json` records their final hashes.

- `vehicle_forklift_red_c01`: articulated counterbalance forklift. Expanded USD instances;
  USDPreviewSurface materials; eight UDIM tiles packed into 4096 × 512 atlases; simplified
  geometry. Uniform scale 0.88, with the rear chassis shortened behind the front axle to fit
  the existing 2 m route envelope. Forks, mast and wheels retain separate scene identities.
  This adapted model is illustrative, not a dimensional specification of real equipment.
- `rack_bulk_storage_a03`: three instances replace the entire near rack row. The original
  long beams span that row, so deleting only one bay would leave damaged beams. These are
  lower, open shelves; their appearance differs deliberately from the original loaded racks.
- `pallet_a01`: resized to the existing 1 × 1.8 × 0.14 m transport cradle. Replaces the pallet
  under each moving batch and the six empty pallets in the existing stack.

The original objects are removed from the visible scene, rather than overlaid. The forklift
is disabled; pallet and rack triangles are cut out before applying the static lightmap. Vertex
UVs, including Lightmap coordinates, are retained. Old per-face import bookkeeping is removed
because it no longer matches the triangle list.

## Preview limits

The forklift has no driver. Static lighting is the existing bake: the surrounding floor retains
the old racks' indirect lighting/shadows. A final art pass would rebake lighting after a model
choice is accepted. Measurements from Simulator do not establish physical iPhone performance.
No ERP, telemetry, catalogue models, production data, or app version number is changed.

All three NVIDIA source packages declare CC BY 4.0. The bundled ASSETS.json links each exact
source revision, records modifications and retains a copy of its license.
