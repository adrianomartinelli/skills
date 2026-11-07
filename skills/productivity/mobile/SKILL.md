---
name: mobile
description: Turn every reply into tappable cards (assumptions, decisions, issues, questions) through the harness's question tool, for a user on a phone. Use when the user says they are on their phone, mobile, away from the desk, or asks for interactive replies; also when grilling or any other skill asks questions while this mode is on.
---

The user is on a **phone**: reading is slow and typing is expensive. Every reply becomes a **round** of **cards** the user answers with a tap. Use the harness's question tool (Claude Code: `AskUserQuestion`); a harness without one gets the same cards as numbered text with lettered options. Cards live in chat only, never in an artifact, an HTML page, or a file to open. A prototype the user asked for (see Prototype it) is the one file you send.

The mode is **sticky**: it holds for every reply in the session, inside every other skill, until the user says "desk mode" or "stop mobile".

## A reply

1. **Do the work first.** Read, run, and look up facts before the round; a card asks only what the user alone can decide.
2. **Write one to three chat lines**: what you did and what changed. No tables, no long code blocks.
3. **Ask the round.** Order: assumptions, decisions, issues, questions. One question-tool call holds 4 cards; make as many calls as the round needs, most important first. Done when every open item of this reply is a card.
4. **Act on the answers**, then start the next reply.

**Assumptions gate the work.** On a new task, the first round holds only the assumptions the work rests on (scope, location, target, interpretation of the request). Take no step that depends on one until it is confirmed or revised.

## Cards

Each card is one self-contained idea: a reader with only the phone screen understands it without opening a file. Name things by what they are, not by path alone. Header: the card type (`Assume`, `Decision`, `Issue`, `Question`), or a 12-character topic.

Every card ends with a **More context** option. The question tool adds "Other" for a free-text answer by itself, so the user can always reply in their own words.

| Card | Text | Options |
|---|---|---|
| **Assumption** | "Assumption: <what you take as true>. Right?" | Confirm (Recommended) · the most likely revision · More context |
| **Decision** | "Decision: <what you chose and why, one line>. OK?" | Keep (Recommended) · zero to two real alternatives, each with its trade-off, never filler · More context |
| **Issue** | "Issue: <the problem, one line>" | Track as issue · Ignore · More context |
| **Question** | the question, worded so the first option is your recommendation | your recommended answer (Recommended) · zero to two real alternatives, never filler · More context |

A question with more than three real options keeps the three strongest; the user reaches the rest through "Other".

**Prototype it.** When a Decision or Question card turns on how a state model or logic behaves, or on what a UI looks like, and seeing it run would let the user answer better than reading a line, put a **Prototype it** option on the card in place of the weakest alternative.

## Answers

- **More context**: explain that one card in a short chat paragraph (the why, the trade-off, what it touches), then ask the same card again in the next round.
- **Prototype it**: build the prototype with the `prototype` skill, send its HTML file with the harness's file tool (Claude Code: `SendUserFile`, display `render`) so it opens on the phone, then ask the same card again without the Prototype it option.
- **Track as issue**: create the issue in the project's tracker (`docs/agents/issue-tracker.md`, else `gh issue create`) and report its number in the next chat lines.
- **Other** with free text: read it as the answer; if it changes a card's premise, re-ask the cards that depend on it.

## With other skills

The other skill decides *what* to ask; this skill decides *how*. A grilling round is one round of cards: each frontier question is a Question card with the grilling recommendation as the first option. Open-ended grilling questions stay open: keep options short and let "Other" carry the real answer. Facts stay the agent's job, as in grilling.

After work the user did not watch, `debrief` decides the items: each item is one card, its answers are the options, and its kind is the header.
