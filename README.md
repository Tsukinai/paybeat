# WorkTicker 上班鼓励器

macOS 桌面悬浮卡片 + 菜单栏，实时显示今天已经赚了多少钱。

- 今日已赚（每 0.1 秒刷新）、每秒进账、时薪、日薪
- 已工作时长、距下班时间、进度条，午休时金额暂停增长
- 按发薪周期累计本期已赚，显示距发工资天数
- 新币 / 人民币切换，汇率来自 open.er-api.com，每 6 小时刷新

## 安装

### 下载

到 [Releases](https://github.com/Tsukinai/work-ticker/releases) 下载 `WorkTicker-x.y.z.dmg`，打开后把 WorkTicker 拖进"应用程序"。需要 macOS 15+，支持 Apple 芯片和 Intel。

app 没有经过 Apple 公证，第一次打开会被系统拦下。到"系统设置 > 隐私与安全性"，在页面下方点"仍要打开"。也可以在终端执行：

```sh
xattr -dr com.apple.quarantine /Applications/WorkTicker.app
```

开机自启：到"系统设置 > 通用 > 登录项与扩展"，在"登录时打开"里点"+"，添加 WorkTicker。

### 从源码安装

需要 macOS 15+ 和 Swift 6（Xcode 或 Command Line Tools）。

```sh
./install.sh
```

编译并安装到 `/Applications/WorkTicker.app`，同时添加登录启动项。改代码后重新运行即可更新。

`./release.sh` 会编译通用版本并打包成 `.build/WorkTicker-<版本号>.dmg`，版本号在 `Info.plist` 里改。

## 使用

- 点大金额，或右键卡片 / 菜单栏：切换新币和人民币
- 卡片右上角"–"：隐藏卡片；左键点菜单栏金额：显示或隐藏卡片
- 拖动卡片任意位置移动，位置会记住

## 配置

右键卡片或菜单栏，选"设置…"，可以改月薪、上下班时间、午休、发薪日，保存后立即生效。

配置保存在 `~/.config/work-ticker/config.json`（首次运行生成）：

```json
{
  "lunchEnd" : "13:30",
  "lunchStart" : "12:00",
  "monthlySalarySGD" : 5000,
  "payDay" : 30,
  "workEnd" : "18:30",
  "workStart" : "10:00"
}
```

直接改这个文件的话，要重启程序才生效。

## 算法

- 日薪 = 月薪 / 本期工作日数。本期指上个发薪日次日到本月发薪日，工作日只算周一到周五，不含公众假期。发薪日下班时，本期已赚正好等于月薪
- 发薪日超过当月天数时（如 2 月 30 号），按当月最后一天算
- 卡片上的时薪、日薪两格按每月 20 天、每天 8 小时显示
