# Agents Coding Collab

简体中文 | [English](README.md)

Agents Coding Collab 是一个面向 Codex 的多技能、多模型编码协作插件。它把“资料检查、模型路由、长工程上下文、协作脚本运行、最终审查”拆成一组可组合的 skills，让 Codex 能在真正动手写代码前先理解项目规则和当前资料，再把任务交给多个 OpenAI 兼容模型协作完成。

## 它解决什么问题

- 不是只让一个模型直接写代码，而是让 writer、reviewer、reviser、validator 分工协作。
- 不是只支持两个固定模型，而是支持多个模型、多个请求地址和多组 API Key。
- 不是只适合小函数，而是能按任务复杂度选择 quick 或 long edit。
- 不是盲信模型记忆，而是要求 Codex 主动使用工具、官方文档、互联网搜索和项目内规则。
- 不是模型生成完就交付，而是要求当前 Codex 做最后总审。

## 内置 Skills

- `agents-coding-collab`：主入口，描述整体协作流程和脚本参数。
- `agents-coding-research`：在编码前收集项目规则、官方文档、互联网资料和 freshness evidence。
- `agents-coding-model-router`：选择 writer、reviewer、reviser、validator 使用的模型、Base URL 和 API Key。
- `agents-coding-long-edit`：为大型工程、跨文件修改、迁移、UI 流程等任务准备上下文包。
- `agents-coding-runner`：安全运行 `scripts/collab.ps1`，处理超时、产物和后台进程卫生。
- `agents-coding-final-review`：由 Codex 对生成产物做最终审查，检查遗漏、不稳定点、测试和项目规则匹配度。

## 主要能力

- 支持 OpenAI 兼容 API。
- 支持 writer、reviewer、reviser、validator 分别指定模型。
- 支持每个角色独立配置请求地址和 API Key。
- 支持多个 reviewer 使用不同模型、不同网关、不同 Key。
- 支持 quick 模式处理小型低风险任务。
- 支持 long edit 模式处理大型工程和跨文件修改。
- 要求 Codex 在涉及过时风险时主动查官方文档、互联网和项目本地规则。
- 要求 Codex 在最终交付前亲自总审。

## 目录结构

```text
.codex-plugin/plugin.json
skills/
  agents-coding-collab/
    SKILL.md
    scripts/collab.ps1
  agents-coding-research/
  agents-coding-model-router/
  agents-coding-long-edit/
  agents-coding-runner/
  agents-coding-final-review/
```

## 从源码使用

克隆本仓库后，把仓库根目录作为 Codex 插件目录使用。插件 manifest 位于：

```text
.codex-plugin/plugin.json
```

本地开发时，仓库根目录就是插件根目录。

## 基础脚本用法

进入 `skills/agents-coding-collab` 后运行：

```powershell
.\scripts\collab.ps1 -Task "写一个防抖函数" -Language javascript -Quick
```

大型工程 / long edit 示例：

```powershell
.\scripts\collab.ps1 -Task "<上下文包>" -Language typescript -ReviewerCount 4 -MaxRounds 5 -RequestTimeoutSec 0
```

多 reviewer / 多模型 / 多网关示例：

```powershell
.\scripts\collab.ps1 -Task "<上下文包>" -Language typescript -ReviewerCount 4 `
  -WriterModel model-writer -WriterBaseUrl "https://writer.example" -WriterApiKey $env:WRITER_KEY `
  -ReviewerModels model-bug,model-security,model-performance,model-requirements `
  -ReviewerBaseUrls "https://review-a.example","https://review-b.example" `
  -ReviewerApiKeys $env:REVIEW_A_KEY,$env:REVIEW_B_KEY `
  -ValidatorModel model-validator -ValidatorBaseUrl "https://validator.example" -ValidatorApiKey $env:VALIDATOR_KEY
```

## API Key 规则

不要把 API Key 提交到仓库。脚本按以下方式读取 Key：

- `-ApiKey`
- `XD_API_KEY`
- `-WriterApiKey`、`-ReviewerApiKey`、`-ValidatorApiKey` 等角色参数
- `AGENTS_CODING_WRITER_API_KEY` 等角色环境变量
- `%USERPROFILE%\.codex\secrets\dual-model-collab.key` 作为本机私有兜底

私有兜底文件故意放在仓库外，不应该复制进仓库。

## 推荐工作流

1. Codex 先从产品角度理解用户需求，并判断 quick 还是 long edit。
2. 如果任务涉及可能过时的信息，先用 `agents-coding-research` 查项目规则、官方文档和互联网资料。
3. 如果要使用多个模型或多个 API 网关，用 `agents-coding-model-router` 做角色路由。
4. 如果是大型工程，用 `agents-coding-long-edit` 生成上下文包。
5. 用 `agents-coding-runner` 运行协作脚本，并等待模型完成。
6. 用 `agents-coding-final-review` 做最终总审，再交付给用户。

## 验证

可用的本地检查：

```powershell
python <path-to-skill-creator>\scripts\quick_validate.py .\skills\agents-coding-collab
python <path-to-plugin-creator>\scripts\validate_plugin.py .
```

PowerShell 脚本语法检查：

```powershell
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  ".\skills\agents-coding-collab\scripts\collab.ps1",
  [ref]$tokens,
  [ref]$errors
) | Out-Null
if ($errors.Count -gt 0) { $errors } else { "PowerShell syntax OK" }
```

## 许可证

MIT。
