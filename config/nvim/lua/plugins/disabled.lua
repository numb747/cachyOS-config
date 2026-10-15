return {
  -- disable trouble
  { "bufferline.nvim", enabled = false },

  -- lang.sql 扩展自带的数据库客户端（DBUI / :DB / 连库补全），用不上（2026-10-15）。
  -- 扩展本身留着：SQL 的 treesitter 高亮和 sqlfluff 检查/格式化还要用。
  { "kristijanhusak/vim-dadbod-ui", enabled = false },
  { "kristijanhusak/vim-dadbod-completion", enabled = false },
  { "tpope/vim-dadbod", enabled = false },
  -- 扩展把 dadbod 塞进了 blink 的【全局】补全源，插件关了这里不摘，所有文件补全都会报找不到模块。
  {
    "saghen/blink.cmp",
    opts = function(_, opts)
      local sources = opts.sources or {}
      sources.default = vim.tbl_filter(function(s)
        return s ~= "dadbod"
      end, sources.default or {})
      if sources.providers then
        sources.providers.dadbod = nil
      end
    end,
  },
}
