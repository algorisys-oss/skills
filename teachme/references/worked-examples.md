# Worked examples — design and fading

A **worked example** is a problem solved step by step with the *reasoning* exposed. For novices,
studying worked examples produces more learning per minute than attempting problems cold (the
**worked-example effect**), because it spends the learner's limited working memory on understanding
the method instead of on flailing search. This file is how to build them well and how to fade them.

## What makes a worked example *teach* (not just demonstrate)

- **Expose the reasoning, not just the steps.** The value is in *why each move was chosen*. "We
  parameterize here **because** the value is user-controlled" teaches; showing the final query does
  not.
- **Show a dead-end or a rejected option.** "The obvious move is X; that fails because… so instead
  we…". Experts' real process includes pruning; hiding it makes the method look like magic.
- **Sub-goal labels.** Group steps under the goal they serve ("**Validate input** → … **Build the
  query** → …"). Learners who see sub-goals transfer to new problems far better.
- **One example, one principle.** If an example illustrates three ideas, the learner can't tell
  which detail mattered. Strip it to the target idea.
- **Minimize split attention.** Keep the explanation next to the step it explains, not in a separate
  block the learner has to mentally stitch together.

## Self-explanation prompts (this is where Socratic meets worked examples)

Don't narrate a finished example in silence — interleave prompts that make the learner explain it:
- *Before* a step: "What do you think the next move is, and why?" (prediction)
- *After* a step: "Why did that work?" / "What would break if we skipped it?"
- *At the end*: "Summarize the method in one sentence." / "Where would this *not* apply?"

Self-explanation is the single highest-leverage add-on to a worked example. It keeps the load low
(the solution is right there) while forcing the generative work that makes it stick.

## The fade — worked → faded → independent

This is the core progression. Move along it as the learner succeeds; back up on failure.

1. **Worked example (I do):** every step shown, reasoning exposed, with self-explanation prompts.
2. **Faded / completion example (we do):** the same shape with one or more steps **blanked out** for
   the learner to fill. Start by fading the *last* step (easiest), then earlier and more steps each
   cycle. Completion problems beat blank-page problems for intermediate learners.
3. **Independent problem (you do):** a fresh problem, no scaffold. This is the transfer test.

Pair them: an **example–problem pair** (study a worked example, then immediately solve a matched
problem) outperforms a block of examples followed by a block of problems.

## Expertise-reversal — when to stop using worked examples

Worked examples help novices and *hinder* experts: once the method is known, studying a full
example is redundant load and feels patronizing. So:

- **Novice:** mostly worked examples + heavy self-explanation prompting.
- **Developing:** faded/completion examples; fade faster each success.
- **Proficient:** drop examples; give open problems and use the Socratic playbook on their attempts.

Diagnose level before choosing (see `socratic-method.md` → Diagnostic questions), and re-diagnose as
you go — a learner who nails two faded examples is telling you to fade harder.

## For code specifically

- Prefer examples from the **user's own repo** — relevance and transfer are higher.
- **Run the example.** Real output beats asserted output, and a failing run is a free
  prediction-vs-reality misconception check.
- Keep examples runnable and minimal — no unrelated scaffolding competing for attention.
