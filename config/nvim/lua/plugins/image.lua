-- image.nvim —— 终端内联图片渲染,统一承担两件事,取代 snacks.image:
--   1) 直接打开图片文件(:e x.png / mini.files 里按 l)就地渲染成图,不再是一屏二进制
--   2) 给 molten 当图像 provider,把 kernel 回传的 matplotlib / PNG 画进 cell 输出
--
-- 为什么从 snacks.image 切过来:molten 的 provider 只认 none / image.nvim / wezterm,
-- 不认 snacks(rplugin/python3/molten/images.py)。想让"打开图片文件"和"molten 预览图"
-- 走同一套机制、只维护一处,就只能统一到 image.nvim。snacks.image 那边已关(见 snacks.lua)。
--
-- 为什么以前躲着它:image.nvim 默认 processor 是 "magick_rock",要 magick luarock(FFI
-- 绑定),得先有一套能用的 luarocks —— 本机没装 luarocks,这正是当初放弃它的原因。
-- 但它还有 processor = "magick_cli":直接 shell out 到系统 ImageMagick 的
-- magick/convert/identify,零 luarock。本机 /usr/bin/magick(IM7 7.1.2)正好够用。
return {
  "3rd/image.nvim",

  -- ★ build = false:阻止 lazy.nvim 去 luarocks 装/编 magick rock。
  --   我们走 CLI 不需要它;而没有 luarocks 时那步 build 一定失败,插件直接装不上。
  --   见 image.nvim#91。
  build = false,

  -- ★ 不懒加载。两个理由:
  --   1) molten 是 lazy=false 的 remote plugin,渲染图时要现成的 image.nvim API;
  --   2) "打开图片文件即渲染"靠 hijack 注册的 BufReadCmd,启动即就位才拦得住 :e。
  lazy = false,

  opts = {
    -- 下面两项其实都是 image.nvim 的默认值,显式写出是因为它们就是这套方案的要点:
    -- kitty graphics protocol,最快最稳(你在 kitty 0.48)。alacritty 不支持,会瞎。
    backend = "kitty",
    -- ★ CLI 处理器,用系统 ImageMagick,完全不碰 luarock。
    processor = "magick_cli",

    -- markdown 正文里的图片内联渲染(原先 snacks.doc.inline 干的活),其余走默认
    integrations = {
      markdown = { enabled = true },
    },

    -- 打开单独图片文件就渲染(原先 snacks.image 干的活)—— 默认已开,
    -- 走 hijack_file_patterns(png/jpg/jpeg/gif/webp/avif),挂在 BufWinEnter 上。

    -- 单张图最高占窗口一半,防巨图铺满
    max_height_window_percentage = 50,

    -- 被别的浮窗盖住时自动清掉,避免 kitty 图像残影糊在界面上
    window_overlap_clear_enabled = true,
  },
}
