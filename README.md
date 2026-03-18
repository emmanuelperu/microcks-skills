# Microcks Agent Skills

[![License](https://img.shields.io/github/license/emmanuelperu/microcks-skills)](LICENSE)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-compatible-blue)](https://agentskills.io)
[![Microcks](https://img.shields.io/badge/Microcks-CNCF%20Sandbox-9cf)](https://microcks.io)
[![GitHub stars](https://img.shields.io/github/stars/emmanuelperu/microcks-skills)](https://github.com/emmanuelperu/microcks-skills/stargazers)
[![Skills](https://img.shields.io/badge/skills-3-green)](skills/)

Agent skills for [Microcks](https://microcks.io) — the CNCF open-source tool for API mocking and testing. These skills teach AI coding agents how to work with Microcks in your development workflow.

## Skills

| Skill | Description |
|-------|-------------|
| [microcks-local-server](skills/microcks-local-server/) | Start a local Microcks server with Docker Compose for API mocking and testing |
| [microcks-openapi-mocking](skills/microcks-openapi-mocking/) | Write OpenAPI examples that work with Microcks dispatchers for API mocking |
| [microcks-import-artifacts](skills/microcks-import-artifacts/) | Import OpenAPI specs into Microcks and auto-configure dispatchers |

## Quick Install

```bash
# Install all skills
npx skills add emmanuelperu/microcks-skills

# Install for a specific agent
npx skills add emmanuelperu/microcks-skills -a claude-code
npx skills add emmanuelperu/microcks-skills -a cursor
npx skills add emmanuelperu/microcks-skills -a copilot
```

## Compatible Agents

These skills work with any agent that supports the [Agent Skills](https://agentskills.io) specification:

- Claude Code
- Cursor
- GitHub Copilot
- Windsurf
- And more

## Complementary Skills

| Skill | Repository | Description |
|-------|------------|-------------|
| openapi-spec-generation | [wshobson/agents](https://github.com/wshobson/agents) | Patterns for creating and validating OpenAPI specifications |

```bash
npx skills add https://github.com/wshobson/agents --skill openapi-spec-generation
```

## Links

- [Microcks](https://microcks.io) — API mocking and testing platform
- [Agent Skills](https://agentskills.io) — Open specification for AI agent skills

## Acknowledgments

Some parts of these skills were written with the help of [Claude](https://claude.ai).

## License

Apache 2.0
