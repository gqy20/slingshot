# S01E06 素材与数据来源清单

原则：轨道关系、参考系变换和导航误差动画由项目自行生成；真实影像只有在授权条件明确后才进入成片。

| 段落 | 画面 | 处理方式 | 来源/制作位置 | 状态 |
|---|---|---|---|---|
| 冷开场 | 地球固定、目标绕圈 | Godot 程序动画 | `orbital_companion_canvas.gd` | 自制 |
| 热点锚点 | 天问二号抵达、20 km、400 天、10 亿 km | 自制信息动画；不截图新闻页 | CNSA 事实数据 | 自制 |
| 日心揭示 | 太阳、地球、目标两条轨道 | Godot 程序动画 | 概念求解器 RunRecord | 自制 |
| 快慢因果 | 日心距离与角速度同步条 | Godot 程序动画 | 概念求解器 RunRecord | 自制 |
| 参考系切换 | 惯性系连续变换为共转系 | Godot 坐标变换 | 同一 RunRecord | 自制 |
| 共振 | 长期相对轨迹保持在附近 | JPL Horizons 2010–2050 星历投影 + 2% 周期差概念对照 | `data/ephemerides/` 与轨道 Canvas | 已自制；力学拆解待做 |
| 真卫星对照 | 月球地心轨道与准卫星日心轨道 | Godot 示意动画 | 左右不同尺度并明确标注，天体大小非比例 | 已自制 |
| 交会 | 未来相遇点、位置差与速度差同步收敛 | Godot 示意动画 | 非真实任务轨迹和控制量 | 已自制 |
| 光学导航 | 五次视线观测加入，不确定椭圆由百千米量级收缩至千米量级 | Godot 数据动画 | CNSA 公布量级；椭圆不按数值线性缩放 | 已自制 |
| 实物锚点 | 2026-07-02 的 2016 HO3 图像 | 原图保存在 `assets/video/tianwen2/sources/`；预览中保留嵌入式标志与比例尺，并标注来源 | [CNSA 官方发布](https://www.cnsa.gov.cn/n6758823/n6758838/c10760422/content.html) | 已接入预览；公开发布前复核授权 |
| 实物锚点 | 天问二号圆形柔性太阳翼 | 原图保存在 `assets/video/tianwen2/sources/`；用于品牌门槛和任务抵达镜头的确定性裁切、缓慢推近 | [CNSA 官方发布](https://www.cnsa.gov.cn/n6758823/n6758838/c10680040/content.html) | 已接入预览；公开发布前复核授权 |
| 实物锚点 | 天问二号与地球合影 | 原图保存在 `assets/video/tianwen2/sources/`；用于科学收束镜头，不伪装为动态摄影 | [CNSA 官方发布](https://www.cnsa.gov.cn/n6759533/c10706693/content.html) | 已接入预览；公开发布前复核授权 |
| 参考系证据 | 2016 HO3 日心轨道资料图 | 原图短暂建立“日心轨道 + 地球附近包络”，随后切回同一 RunRecord 的双参考系程序动画 | [NASA/JPL-Caltech](https://www.jpl.nasa.gov/news/small-asteroid-is-earths-constant-companion/) | 已接入预览；按 JPL Image Use Policy 复核署名 |
| 月球对照证据 | 天问二号窄视场导航敏感器拍摄的地球与月球 | 两张原图并置，精确标注器地、器月均约 59 万 km；不据图推断天体真实比例 | [CNSA 官方发布](https://www.cnsa.gov.cn/n6758823/n6758838/c10684432/content.html) | 已接入预览；公开发布前复核授权 |
| 天体组件 | 太阳、地球、月球的表面与边缘光 | NASA 官方纹理 + Godot 球面映射；保留项目内统一轮廓光 | SDO、Blue Marble、CGI Moon Kit；见 `assets/video/celestial/README.md` | 已接入并通过局部运动预览 |

## 外部资源使用决定

### 不直接使用

- 新闻网页截图、社交平台转发图和带平台 UI 的视频。
- NASA/JPL 的现成轨道动画：仅用于科学核对，不作为最终镜头。
- 素材站星空、AI 生成探测器或 AI 生成小行星“实拍”。它们会把证据和装饰混在一起。

### 可以复用

- 项目现有品牌 stinger、字体、BGM 和音效体系。
- JPL/Horizons、CNSA/CLPDS 的数值数据；导入时保存查询参数与署名说明。
- NASA SDO 太阳全圆盘、NASA Earth Observatory Blue Marble 地球纹理、NASA SVS/LRO CGI Moon Kit 月球纹理；按各资产页标注来源，不使用 NASA 标志，不暗示官方背书。

## 署名与授权备注

- CNSA 页面存在版权声明，目前未发现对新闻图片的通用再利用许可。真实小行星照片在许可确认前不得打包进成片。
- 如后续采用 JPL 可复用资产，按具体资产页和 JPL Image Use Policy 标注 `Courtesy NASA/JPL-Caltech`，且不得暗示官方背书。
- 数据事实不等于图片版权；两者分别记录。

## 1080p 字号底线

- 所有承担来源、条件、数值、模型边界或箭头含义的文字不小于 30 px；主要正文从 32 px 起。
- 结论与必要条件优先不小于 34 px，关键读数维持 38 px 以上。
- 原图中自带的小字只作为原始影像内容保留；凡需观众读取的信息，必须另用项目字体确定性覆写。

## 星历生成记录

- 生成脚本：`scripts/fetch_horizons_ephemeris.ps1`
- 数据文件：`data/ephemerides/2016-ho3-earth-2010-2050.json`
- 对象：`469219` 与地球质心 `399`
- 中心：太阳中心 `500@10`
- 坐标：ICRF、J2000 黄道平面
- 单位：AU、AU/day
- 历元：2010-01-01 至 2051-01-01，每 10 天
- 文件保存每个 Horizons 原始响应的 SHA-256；画面使用黄道二维投影，三维 `z` 数据仍保留在 RunRecord。
