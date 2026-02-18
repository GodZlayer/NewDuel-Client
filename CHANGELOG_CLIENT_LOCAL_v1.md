# CHANGELOG_CLIENT_LOCAL_v1

## Repo
- `NewDuel-Client` (`OpenGunZ-Client`)

## Entrega (Modelos rs3_model_v1 a partir de GLB)
- Gerado grafo de assets em `../docs/model_asset_graph_v1.md` e `../docs/model_asset_graph_v1.json`.
- Gerados assets abertos em `system/rs3/open_assets/**`:
- `character/*`, `parts/*`, `weapon/*` com `model.glb` + `source_meta.json`.
- `open_assets_manifest_v1.json`.
- `conversion_report_open_assets_v1.md`.
- Gerados pacotes runtime em `system/rs3/models/**`:
- `model.json`, `mesh.bin`, `skeleton.bin`, `anim.bin`, `materials.bin`, `attachments.json`.
- `rs3_model_manifest_v1.json`.
- `conversion_report_rs3_model_v1.md`.
- Escopo desta leva executada sobre minset local (com faltas explicitadas no manifesto de open assets).

## Entrega (Texturas PNG de pacote RS3 - char_creation_select)
- Mantida politica: sem alterar assets fonte em `ui/Char-Creation-Select`.
- Gerados no pacote RS3:
- `system/rs3/scenes/char_creation_select/textures/*.png`
- `system/rs3/scenes/char_creation_select/texture_manifest_v1.json`
- `system/rs3/scenes/char_creation_select/conversion_report_textures_v1.md`
- `scene.json` atualizado com:
- `textureManifest`
- `materials[].packageTexture`
- `usedMaterialIndices[]`
- `world.bin` atualizado para `diffuseMap` local `textures/*.png` nos materiais usados.

## Resultado tecnico desta leva
- Materiais usados: `27`
- PNGs convertidos: `27`
- Materiais usados faltando: `0`
- Escopo fechado desta fase: textura+alpha para mapa offline `char_creation_select`.
- Fora do escopo desta fase: `LM` e `OBJECTLIST` animado.

## Entrega
- Adicionado `system/rs3/item_minset_spec_v1.json` com IDs fixos e alias `sword01 -> sword_wood`.
- Adicionado `tools/minset/generate_item_minset.ps1` para gerar:
- `system/rs3/item_minset_v1.json`
- `system/rs3/item_aliases_v1.json`
- `system/rs3/item_keep_manifest_v1.txt`
- `system/rs3/item_minset_report_v1.md`
- Adicionado `tools/minset/apply_item_prune.ps1` com modos `-DryRun` e `-Apply`.
- Aplicada poda conservadora:
- `Model/weapon`: removidos do runtime apenas `.elu/.ani` fora do manifesto.
- `Model/man` e `Model/woman`: removidos do runtime apenas `*-parts*.elu` fora do manifesto.
- Arquivos removidos do runtime foram movidos para:
- `OpenGunZ-Client/_legacy_archive/items/20260217_041317/...`

## Resultado da poda
- Candidatos movidos: `300`
- `weapon (.elu/.ani)`: `140`
- `man (*-parts*.elu)`: `82`
- `woman (*-parts*.elu)`: `78`
- Dry-run pós-apply: `0` candidatos pendentes.

## Checklist de validação
- [x] Minset resolve IDs definidos (alias `sword01 -> sword_wood` aplicado).
- [x] `apply_item_prune.ps1 -DryRun` gera relatório consistente.
- [x] `apply_item_prune.ps1 -Apply` arquiva em `_legacy_archive` sem delete direto.
- [x] `zitem.xml`, `parts_index.xml`, `weapon.xml` mantidos como referência.

## Entrega (Char-Creation-Select RS3 Scene Package L1)
- Adicionado pacote convertido nativo em `system/rs3/scenes/char_creation_select/`:
- `scene.json`
- `world.bin`
- `collision.bin`
- `conversion_report.md`
- Fonte de conversao: `ui/Char-Creation-Select` (`Login.RS`, `Login.RS.xml`, `Login.RS.bsp`, `Login.RS.col`).
- Auditoria incluida no report com contagens e hashes SHA-256.

## Checklist de validacao (assets)
- [x] `scene.json` contem `camera_pos 01`, `camera_pos 02`, `spawn_solo_101`, `fog`, `lights`.
- [x] `world.bin` e `collision.bin` gerados para runtime nativo.
- [x] Nenhum parser RS2 foi reintroduzido no caminho de runtime do client.
