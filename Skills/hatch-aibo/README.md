# Hatch Aibo Skill

English · [简体中文](#简体中文)

Generate a custom [Aibo](https://github.com/fenxer/agent-aibo) / Petdex pet from a name, description, or reference image.

Default is **V2**: per-state animation clips, plus 16 look facings for follow-mouse. The run costs about **10–12 image gens** (not one image per frame). Primary output is an Aibo clip pack (`aibo.json` + `clips/`); it also writes a Codex/Petdex `pet.json` + `spritesheet.webp`.

Ask your Agent to install this skill (this folder), then to hatch a pet. It will ask about per-state action overrides and which image-gen host to use before generating.

## vs hatch-pet

hatch-pet is the original Codex pet pipeline (8×9 atlas, `$imagegen`, connected-component strip cuts). hatch-aibo keeps the same gen budget and row layout, and changes the parts that broke down at pet size:

- **V2 by default** — rows 9–10 are look facings. V1 (animation only) only if you ask.
- **Aibo pack first** — `clips/` + `aibo.json` for the Mac app; spritesheet is a side export, not the only deliverable.
- **Gutter split + shared camera** — poses are generated with chroma gaps, sliced on 1D gaps, then one scale/baseline per standing identity (and one scale per jumping / failed / run cycle). hatch-pet grouped connected components and `fit_to_cell` each frame, so crouches zoomed in and feet jumped.
- **Redo one row** — a bad strip is redrawn; you do not rerun all 12 gens.
- **Host is a choice** — whatever image-gen tool the Agent already has. Scripts never call an image API.

Details: `SKILL.md`, `references/`.

---



## 简体中文

根据名字、描述或参考图，生成一只自定义 [Aibo](https://github.com/fenxer/agent-aibo) / Petdex 宠物。

默认 **V2**：各状态动画 clips，外加 16 个朝向（跟鼠标）。一次大约 **10–12 张生图**（不是一帧一张）。主产物是 Aibo clip 包（`aibo.json` + `clips/`），同时写出给 Codex/Petdex 的 `pet.json` + `spritesheet.webp`。

复制链接，让 Agent 安装本目录这个 skill，再让它 hatch 一只宠物即可。开场会问每状态动作要不要改、用哪个生图宿主。

## 相对 hatch-pet

hatch-pet 是原来的 Codex 宠物流程（8×9 图集、`$imagegen`、连通域切条）。hatch-aibo 生图次数和行布局差不多，改的是宠物尺寸下会翻车的部分：

- **默认 V2** — 第 9–10 行是朝向；只有你明确要求才走仅动画的 V1。
- **先交 Aibo 包** — `clips/` + `aibo.json` 给桌面应用；spritesheet 是附带导出，不是唯一交付。
- **色键间隙 + 共享相机** — 生成时姿势之间留 chroma 空隙，按一维间隙切开，站立行统一身高/基线（跳、失败、跑步各状态内再统一缩放）。hatch-pet 用连通域切块再逐帧 `fit_to_cell`，蹲下会放大、脚底会跳。
- **按行返工** — 某一条不好就重画那一条，不必把 12 张全重来。
- **生图宿主自选** — 用 Agent 现成的生图能力即可。脚本自己不调图像 API。

细节见 `SKILL.md` 和 `references/`。