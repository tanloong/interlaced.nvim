#!/usr/bin/env lua

require "interlaced".setup {}
local rpst = require "interlaced.reposition"

---@param func function
---@param sents string[]
---@param sent_sep string
local test_segment = function(func, sents, sent_sep)
  ---@type string[]
  local para_sents
  local paras
  ---@type string[]
  local sents_expected
  local lines

  table.insert(sents, sents[1]) -- insert placeholder ensuring the last sentence's ending is tested
  for start = 1, 2 do           -- ensure each sentence ending is tested
    paras = {}
    for i = start, #sents, 3 do -- test multiple sentences at the same line
      para_sents = {}
      for offset = 0, 2 do table.insert(para_sents, sents[i + offset]) end
      table.insert(paras, para_sents)
    end

    sents_expected = {}
    for _, _sents in ipairs(paras) do
      vim.list_extend(sents_expected, _sents)
    end

    for i = 1, 2 do -- test being tolerant of redundant separators
      lines = {}
      for _, _sents in ipairs(paras) do
        table.insert(lines, table.concat(_sents, vim.fn["repeat"](sent_sep, i)))
      end
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      func { line1 = 1, line2 = vim.fn.line("$") }
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      assert(#lines == #sents_expected,
        string.format("Result has different length than expected.\nResult has %d lines:\n%s\n\nExpected %d lines:\n%s",
          #lines,
          table.concat(lines, "\n"),
          #sents_expected,
          table.concat(sents_expected, "\n")))
      for j, line in ipairs(lines) do
        assert(line == sents_expected[j],
          string.format("Line %d of result is different than expected.\nResult: %s\nExpected: %s", j, line,
            sents_expected[i]))
      end
    end
  end
end

test_segment(
  rpst.cmd.SplitEnglishSentences,
  {
    "The small sign said, “Supervisor.”",
    "The man to whom the sign referred did not look up.",
    "He said, “Where to?”",
    "Gaal wasn’t sure, but even a few seconds hesitation meant men queuing in line behind him.",
    "The Supervisor looked up, “Where to?”",
    "Gaal’s funds were low, but there was only this one night and then he would have a job.",
    "He tried to sound nonchalant: “A good hotel, please.”",
    "The Supervisor was unimpressed.",
    "“They’re all good.",
    "Name one.”",
    "Gaal said, desperately, “The nearest one, please.”",
  }, " ")

test_segment(
  rpst.cmd.SplitChineseSentences,
  {
    "此开卷第一回也。",
    "作者自云：因曾历过一番梦幻之后，故将真事隐去，而借“通灵”之说，撰此《石头记》一书也。",
    "故曰“甄士隐”云云。",
    "但书中所记何事何人？",
    "自又云：“今风尘碌碌，一事无成，忽念及当日所有之女子，一一细考较去，觉其行止见识，皆出于我之上。",
    "何我堂堂须眉，诚不若彼裙钗哉？",
    "实愧则有馀，悔又无益之大无可如何之日也！",
    "当此，则自欲将以往所赖天恩祖德，锦衣纨绔之时，饫甘餍肥之日，背父兄教育之恩，负师友规谈之德，以至今日一技无成，半生潦倒之罪，编述一集，以告天下人：我之罪固不免，然闺阁中本自历历有人，万不可因我之不肖，自护己短，一并使其泯灭也。",
    "虽今日之茅椽蓬牖，瓦灶绳床，其晨夕风露，阶柳庭花，亦未有妨我之襟怀笔墨者。",
    "虽我未学，下笔无文，又何妨用假语村言，敷演出一段故事来，亦可使闺阁昭传，复可悦世之目，破人愁闷，不亦宜乎？”",
    "故曰“贾雨村”云云。",
  }, "")
