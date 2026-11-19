# 运行环境限制

当前接口不支持图片：工具结果里一旦出现图片，请求会报 400（`type 参数非法，取值范围 ['text']`），而且之后整个会话都会报同样的错。所以：

- 不要用 Read 读图片文件（png / jpg / jpeg / gif / webp / bmp 等）。需要图片信息时，用 Bash 查元数据（`file`、`identify`），或者请用户用文字描述。
- 看网页用 `mcp__chrome-devtools__take_snapshot`（文本结构树），不要截图。
- 其他会返回图片的工具也不要调用。
