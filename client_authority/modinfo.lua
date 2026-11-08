name = "Client Authority (experimental) / 客户端权威移动"
description = [[实验性：把移动改成「客户端计算 + 服务端校验」，而不是「服务端说了算」。

校验规则对齐 Minecraft 的 handleMovePlayer：
· 阈值按「移动速度 × 实际包间隔 × 宽容倍数」计算，不是固定每包距离
· 传送、击退、上下载具期间进入静默窗口，丢弃客户端上报
· 序列号单调递增，过期包直接丢弃
· 连续被拒超过阈值时记日志

双端模组，服务器与所有客户端都必须安装。]]
author = "limingzxc"
version = "0.3.0"

api_version = 10
dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
all_clients_require_mod = true
client_only_mod = false
server_only_mod = false
priority = 0

server_filter_tags = { "client authority", "movement" }

icon_atlas = ""
icon = ""

configuration_options = {
    {
        name = "enabled",
        label = "启用",
        hover = "关闭后服务端完全回到原版行为。",
        options = {
            { description = "开", data = true },
            { description = "关", data = false },
        },
        default = true,
    },
    {
        name = "force_predict",
        label = "客户端始终预测",
        hover = "拆掉 CanLocomote 里的 busy / pause 闸门。副作用：可以在砍树、攻击时移动。",
        options = {
            { description = "开", data = true },
            { description = "关", data = false },
        },
        default = true,
    },
    {
        name = "no_pause",
        label = "服务端不再暂停预测",
        hover = "把 RemotePausePrediction 这条通道堵死。必须和「启用」一起开，单独开会让客户端与服务端分叉。",
        options = {
            { description = "开", data = true },
            { description = "关", data = false },
        },
        default = true,
    },
    {
        name = "slack",
        label = "速度宽容倍数",
        hover = "允许的最大位移 = 走路速度 × 实际间隔 × 该倍数。1.5 严格，2.0 默认，3.0 宽松（加速 buff 不易被误拒）。",
        options = {
            { description = "1.5（严格）", data = 1.5 },
            { description = "2.0（默认）", data = 2.0 },
            { description = "3.0（宽松）", data = 3.0 },
        },
        default = 2.0,
    },
    {
        name = "log",
        label = "记录被丢弃的上报",
        hover = "打到 server_log.txt，每 10 秒一行采纳率，被拒时打原因。",
        options = {
            { description = "关", data = false },
            { description = "开", data = true },
        },
        default = false,
    },
}
