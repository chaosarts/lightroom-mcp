# Lightroom MCP Project Plan

## Goal

I first correct my RAW photo in Lightroom Classic to make it look natural. The agent then uses a finished reference image and my corrected photo to derive a look. I can review the look in a preview and approve it for saving as a reusable Lightroom preset.

## Rules for the look

- Protect every control in **Light** and the white balance **Temperature** and **Tint** controls.
- Allow all other Develop settings, including Tone Curve, Color Grading, and Color Mixer. These tools may visibly change brightness and color in the result.
- The MCP validates each proposal before applying it and verifies that the protected values on the virtual copy match their original values. The saved preset includes only permitted settings.
- A finished reference image is sufficient input. Differences in subject and lighting can make visual comparison harder.
- If the agent cannot get sufficiently close with the permitted settings, it reports that explicitly, shows the best tested preview, and describes the visible differences. If it cannot assess the match reliably, it reports that uncertainty. Its conclusions apply to the proposals it tested.

## Implementation in small commits

Each step has a verifiable outcome. If a step grows too large, split it into smaller commits that can each be verified independently.

| Step | Change | Acceptance criteria |
| --- | --- | --- |
| 1 | Connect the Python MCP server to the Lua plug-in and add a status tool. | The MCP client reports that Lightroom is reachable when the plug-in is running and unreachable when the connection is interrupted. |
| 2 | Read and render the selected Lightroom photo. | The MCP returns the selected photo's Develop settings and a rendered preview. If no photo is selected, it reports that clearly. |
| 3 | Apply a manually specified look to a virtual copy. | A proposal with permitted settings produces a visible preview. A proposal with protected settings is rejected. A before-and-after comparison verifies the protected values on the copy. |
| 4 | Save the approved look as a Lightroom preset. | Applying the preset to a second, already corrected photo in Lightroom applies the permitted look settings. Compare the protected values before and after applying it. |
| 5 | Derive a first look from a reference image. | Given the reference and corrected target photo, the agent produces a proposal that Lightroom renders through the existing preview workflow. |
| 6 | Refine proposals using rendered previews. | The agent compares tested previews with the reference, presents the best tested version, and describes visible differences. |
| 7 | Report limitations and uncertainty. | A close match, a clear mismatch, and a case where comparison is difficult each produce an understandable result. The photographer uses the preview to decide whether to save the preset. |

After step 4, the Lightroom workflow can be tested with a manually specified look. After step 7, the MVP covers reference input, preview, approval, preset creation, and reporting when the match falls short.

## Open technical questions

- **Steps 2–3.** Verify which Develop settings the SDK can read and write in Lightroom Classic. Identify the SDK keys for the protected controls and test the safeguard against them.
- **Step 4.** Verify how to save a reusable preset that appears in Lightroom.
- **Steps 5–7.** Use sample image pairs to determine which visual features are useful for comparison and when a match is too uncertain to assess. The photographer uses the preview to judge whether the look is close enough.

## Resuming in a new session

1. Read this plan and the [README](../README.md). Run `git status --short` and `git log -5 --oneline`. Account for work already in progress.
2. Start with the next open step. Keep the change within its acceptance criteria and verify the result. If Lightroom is unavailable for verification, record the pending manual check here.
3. Before ending the session, update the status below with the completed step, verification result, commit hash if available, and the next concrete step.

### Current status

- **Completed.** Step 1. Commit `1338445` introduced `lightroom_status` over `stdio` and the Lightroom SDK socket on local TCP port `47687`. The follow-up fix rebinds the listener after each response and retries during the brief gap between listeners.
- **Verified.** In Lightroom Classic, the MCP client returned `true` for 12 consecutive calls and four concurrent calls. It returned `false` with the plug-in disabled. After re-enabling the plug-in, all 16 calls returned `true` again.
- **Next.** Step 2. Return the selected photo's Develop settings and a rendered preview, with a clear message if no photo is selected.
