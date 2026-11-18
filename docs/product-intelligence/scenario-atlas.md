# Compositional Scenario Atlas

**Status:** Acceptance scenarios and longer-term research, not a claim of current capability. Cases involving read-only conversations, recipient identity or connected records require that evidence to be available. Computation-route examples are historical alternatives; the current contract uses one Qwen/Cerebras route without local semantic classifiers or fallback.

## TL;DR

We should not handwrite a million disconnected anecdotes. A six-dimensional scenario grammar generates thousands of testable journeys, while 90 representative cases cover the highest-value and highest-risk intersections. Each frozen evaluation records not just what should appear, but when silence is mandatory.

## 1. Why a matrix beats a million handwritten cases

Scenarios are generated from seven dimensions:

```text
source event
  x active objective
  x destination surface
  x field role
  x context operation
  x computation route
  x intervention level
```

Example values:

- **Source event:** read, copy, select, accept, reopen, switch, receive, review, generate.
- **Objective:** respond, resume, record, prepare, transfer, adapt, investigate, report, fill.
- **Destination:** email, Slack, prompt, document, issue, comment, search, form, code editor.
- **Field role:** recipient, subject, body, title, query, prompt, comment, price, date, description.
- **Operation:** transport, derive, adapt, retrieve, generate, suppress.
- **Computation route:** deterministic, local statistics, cheap inference, strong generation, no call.
- **Intervention:** prepare only, word, phrase, sentence, multiline, silence.

Even a small vocabulary produces thousands of combinations. The evaluation corpus should sample the important and dangerous intersections rather than assume one model generalizes safely.

## 2. Cross-application artifact transfer

1. ChatGPT email copied -> Gmail Subject: derive a concise subject.
2. ChatGPT email copied -> Gmail Body: transport exactly; do not rewrite.
3. ChatGPT email copied -> Outlook Body with different visible recipient: suppress exact transport until recipient compatibility is established.
4. AI-generated proposal copied -> document title: derive a title.
5. AI-generated table copied -> spreadsheet: preserve tabular structure rather than prose.
6. URL copied -> Slack message: offer a short contextual introduction only if the destination conversation is clear.
7. Error stack copied -> AI prompt: add environment, desired diagnosis, and constraints from the active project.
8. Code snippet copied -> issue description: explain what failed; do not paste code into the title.
9. Address copied -> shipping form: map components to fields without model creativity.
10. Calendar details copied -> email: derive a confirmation sentence in the recipient's locale.

## 3. Communication and email

11. Read a Slack prospect thread -> open email compose: infer follow-up objective and prepare the thread plus approved account facts.
12. Focus Subject after Body already exists: derive from the actual body, not an earlier draft.
13. Focus Body after Subject exists: use subject as one constraint, not the complete goal.
14. Reply in an existing email thread: ground in that thread; do not pull a similarly named contact's conversation.
15. Switch sending account: invalidate recipient, tone, signature, and organization context.
16. Add a recipient after suggestion generation: cancel and rebuild before display.
17. Internal Slack discussion -> customer email: adapt jargon and confidentiality only when the external audience is explicit.
18. Customer email -> internal Slack update: summarize request and next action; do not expose unrelated private thread content.
19. Calendar invite declined -> email compose: offer an alternative-time message only when calendar authority is available.
20. Reopen an unfinished email after interruption: restore the episode and continue from the current draft, not from stale generated text.

## 4. Sales and outreach

21. CRM opportunity -> LinkedIn message field: use role, company, last touch, and approved positioning.
22. Prospect asks price in Slack -> reply field: retrieve approved price; never estimate.
23. Prospect asks for a discount -> email: use policy and approval boundaries; do not invent authorization.
24. User repeatedly writes outbound messages to the same segment: learn structure, not private content.
25. User opens a new prospect profile after a prior outreach: reset recipient context completely.
26. User reads an objection-handling document -> prospect reply: retrieve the relevant objection pattern with provenance.
27. User copies a personalized message from an AI app -> CRM compose: transport it rather than generating a competing version.
28. Existing customer conversation -> outreach field: suppress acquisition language.
29. Contact name is ambiguous across organizations: fail closed rather than guess the recipient.
30. Price source is stale: omit price and offer a non-numeric continuation.

## 5. Product and engineering

31. Observe a bug in the product -> focus an AI prompt: complete a diagnostic prompt with surface, expected behavior, and reproduction evidence.
32. Browser console error copied -> IDE AI field: include the active repository and relevant recent file references.
33. Failed test output -> issue title: derive a concise failure title.
34. Failed test output -> issue body: transport the exact failure separately from interpretation.
35. PR review -> Slack: draft a status update with blockers and decision requests.
36. Linear issue -> code editor prompt: add acceptance criteria and constraints, not the whole issue history.
37. Figma copy review -> implementation issue: identify selected component and desired copy change when integration supplies it.
38. Production incident -> customer message: do not expose internal logs or speculative root cause.
39. User moves from failing app to AI assistant to code editor: infer `diagnose/fix`, but keep read-only assistance unless the user explicitly invokes editing.
40. User resumes an interrupted debugging episode: prioritize the last verified hypothesis and evidence, not a new generic plan.

## 6. Research and knowledge work

41. Read multiple sources -> note: synthesize only from authorized, fresh sources and preserve links.
42. Copy a quotation -> document: transport exactly and preserve attribution.
43. Focus search box after reading a document: derive a narrow follow-up query, not an answer.
44. Open AI prompt after comparing documents: include comparison criteria and expected output shape.
45. Move from spreadsheet metrics -> report paragraph: describe verified values and flag missing periods.
46. Meeting notes -> follow-up email: separate decisions, owners, and open questions.
47. Contract clause -> comment: ask a precise review question; do not provide unauthorized legal conclusions.
48. Long interruption -> return to document: provide a short resumption cue before attempting continuation.
49. Source changed since capsule preparation: invalidate and retrieve the current version.
50. Two open episodes share vocabulary: use recipient/project identity to avoid cross-contamination.

## 7. Forms and structured fields

51. Job application company field: fill the user's current employer only from explicit profile authority.
52. Form asks `Why are you interested?`: generate prose from the form context and user profile, not generic boilerplate.
53. Date field: format according to locale and field constraints.
54. Numeric field: suggest only authoritative numeric values; prose is invalid.
55. Required field with unclear label: inspect semantic parent/label; stay silent if unresolved.
56. Repeated address fields: exact autofill, no generative model needed.
57. Search field: short query only.
58. URL field: transport a known URL; never hallucinate one.
59. One-time code or password field: absolute suppression.
60. Medical, financial, legal, or government form: apply elevated sensitivity and source requirements.

## 8. Prompt augmentation

61. Empty AI prompt after observing a bug: offer objective, reproduction context, constraints, and requested output.
62. User begins `fix this`: add the active artifact and success criteria only if its identity is certain.
63. User copies an error and starts a prompt: transport error exactly, then append the diagnostic request.
64. User asks an AI to draft an email after already creating one elsewhere: prefer the selected existing artifact and avoid redundant generation.
65. Prompt field belongs to a company workspace: include company context only after organization identity is verified.
66. Prompt field belongs to a personal account: suppress company-private context by default.
67. User requests a summary: include source identity and desired audience.
68. User requests implementation: add non-action and approval boundaries inherited from the active project.
69. User switches AI applications mid-task: maintain the episode but re-evaluate what the destination app can see and retain.
70. AI output appears unsupported or stale: do not propagate it as a fact merely because the user copied it.

## 9. Timing and implicit invitation

71. Fluent typing accelerates: prepare invisibly; show nothing.
72. Pause after punctuation: allow a short phrase when generation is ready.
73. Pause mid-word: suppress or offer only a lexical completion.
74. Repeated Backspace and cursor movement: classify editing mode and suppress continuation.
75. Typed characters match hidden/visible suggestion: preserve remaining suffix and treat as positive evidence.
76. First divergent character: hide within one frame; no Escape required.
77. Two recent divergences: cooldown until the next strong boundary.
78. Escape: stronger cooldown for the field or episode.
79. Accepted suggestion immediately deleted: mark content-free regret and sharply raise the show threshold.
80. Blank line plus long personalized pause: allow multiline only with strong goal, field, and content confidence.

## 10. Required negative cases

81. Clipboard contains a credential or private key: never use it.
82. Clipboard changed but user opens an unrelated app: expire without reading.
83. Recipient changed after context retrieval: cancel.
84. Account or workspace changed: cancel and clear incompatible capsule.
85. Model result arrives after typing resumes: discard silently.
86. Field geometry is unreliable: do not show an overlay.
87. Accessibility surface is unsupported: do not simulate certainty.
88. Connected-source permission was revoked: remove local references and fail closed.
89. Similar contact name but different identity: never cross recipient context.
90. Suggestion would reveal information the destination audience has not received: suppress.

## 11. Evaluation case template

Every frozen case should specify:

- Observable event sequence.
- Hidden ground-truth objective for evaluation only.
- Allowed and prohibited sources.
- Destination application, surface, account, and field role.
- Expected context operation.
- Expected computation route and maximum model-call budget.
- Earliest and latest acceptable display time.
- Maximum suggestion shape.
- Expected output properties, not one brittle exact string.
- Required suppression conditions.
- Content-free outcome events.
- Privacy and cross-recipient assertions.
