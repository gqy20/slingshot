# Celestial body source assets

本目录保存 EP06 天体组件的官方母资产。`sources/` 中的文件保持原始下载内容，不在母版上裁切、改色或覆盖；Godot 适配版本应另存，并在画面或片尾保留相应信用信息。

## 选定方案

| 天体 | 文件 | 官方来源 | 用途 | 信用信息 |
|---|---|---|---|---|
| 地球 | `sources/earth_blue_marble_2048.jpg` | [NASA Earth Observatory — Blue Marble: Next Generation](https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/) | 2:1 球面纹理；在 Godot 中做正射球面映射、昼夜明暗和轻微大气边缘 | `NASA Earth Observatory` |
| 月球 | `sources/moon_lroc_color_2048.jpg` | [NASA SVS — CGI Moon Kit](https://svs.gsfc.nasa.gov/4720/) | 2:1 球面纹理；使用固定光向与低对比环形阴影，避免小尺寸高频闪烁 | `NASA's Scientific Visualization Studio` |
| 太阳 | `sources/sun_sdo_full_disk.jpg` | [NASA SVS — SDO Observes Fast-Growing Sunspot](https://svs.gsfc.nasa.gov/11211/) | 全圆盘观测图；取圆盘区域并叠加项目内的低频光晕，不使用原图底部时间戳 | `NASA/GSFC/SDO` |

`sources/sun_sdo_1024.jpg` 是同一 SDO 资料页的局部活动区候选，细节漂亮但不适合当前全圆盘组件，暂不进入成片。

## 文件校验

- `earth_blue_marble_2048.jpg`: `9304943928E5A2A3EDB8EA37EC2D4C786C81355157B0130EF827DFAB0AC8D206`
- `moon_lroc_color_2048.jpg`: `F7130A1822681FA7512D7DCFD40DB8C10B9BA4F06777910348698260ED7A2170`
- `sun_sdo_1024.jpg`: `806449B0192ED318D27D9F3247F90AEEB512AD9E90255F487DC035AA478F0A49`
- `sun_sdo_full_disk.jpg`: `0F9032121260AE9BAC10D52558F2CAF3B3305371224B1568377DE55275E3D5F3`

## 使用边界

- NASA 媒体通常可用于教育和信息性用途，但应注明 NASA 为来源，不得暗示 NASA 为项目或产品背书；若资产页标注第三方版权，应另行确认。
- 原始地球和月球文件是经纬度矩形纹理，不能直接压成圆形；必须进行球面采样，否则大陆和月面会在圆盘边缘产生错误拉伸。
- 小于约 18 px 半径时不强行显示完整纹理，改用纹理平均色、明暗半球和轮廓光，避免手机端出现摩尔纹与闪烁。
- 天体大小仍为示意，不得让真实表面纹理暗示画面尺度按比例。
