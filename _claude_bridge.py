#!/usr/bin/env python3
"""
Multi-Session Claude Autonomous Development Supervisor
Monitors ALL active Claude sessions across all game repositories:
- make-games (Dice Fate)
- survivors-game (SurvivorQuest)
- first-vibecode-game (Cozy Critter)
Auto-answers interactive questionnaires, unblocks permissions,
and issues continuation prompts so development runs continuously 24/7.
"""

import subprocess
import time
import json
import os
import sys
from datetime import datetime

LOG_FILE = "/home/renovibe79/make-games/claude-bridge.log"
HERDR = "/home/renovibe79/.local/bin/herdr"

def log(msg: str):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    entry = f"[{timestamp}] {msg}\n"
    print(entry, end="", flush=True)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(entry)

def run_cmd(cmd_list, timeout=30):
    try:
        res = subprocess.run(cmd_list, capture_output=True, text=True, timeout=timeout)
        return res.stdout.strip()
    except subprocess.TimeoutExpired:
        return ""
    except Exception as e:
        log(f"Error running {cmd_list}: {e}")
        return ""

def list_claude_agents():
    out = run_cmd([HERDR, "agent", "list"])
    agents = []
    try:
        data = json.loads(out)
        for ag in data.get("result", {}).get("agents", []):
            if ag.get("agent") == "claude":
                agents.append({
                    "pane_id": ag.get("pane_id"),
                    "status": ag.get("agent_status"),
                    "cwd": ag.get("cwd", ""),
                    "title": ag.get("terminal_title_stripped", "")
                })
    except Exception as e:
        log(f"Failed to parse herdr agent list: {e}")
    return agents

def get_recent_terminal(pane_id, lines=40):
    return run_cmd([HERDR, "pane", "read", "--lines", str(lines), pane_id])

def generate_continuation_prompt(cwd: str, terminal_text: str) -> str:
    lower = terminal_text.lower()
    
    if "survivors-game" in cwd:
        if any(q in lower for q in ["how should", "what should", "should i", "shall i", "proceed"]):
            return "Please proceed with the recommended option (Milestone 4 Part 2 / next planned milestone). Run tests with godot --headless and keep development moving."
        return "Please continue implementing the next tasks in the autonomous development roadmap. Ensure headless tests pass and commit milestones cleanly."
    
    if "first-vibecode-game" in cwd:
        if any(q in lower for q in ["how should", "what should", "should i", "shall i", "proceed"]):
            return "Yes, proceed with the recommended enhancement from PHASE_3_IMPLEMENTATION_PLAN.md. Ensure all bug-verify and gameplay tests pass."
        return "Please continue implementing the Phase 3 enhancements and polishing features in the roadmap. Ensure tests pass cleanly."

    # make-games / default
    if any(q in lower for q in ["should i", "shall i", "would you like", "want me to", "proceed with", "next step", "what should", "how should"]):
        return "Yes, proceed with the recommended option. Follow PLAN.md strictly, ensure `godot --headless --path . -s test.gd` passes, and move to the next item."
    return "Please continue implementing the next tasks in PLAN.md. Ensure all headless tests in test.gd pass cleanly."

def handle_blocked_agent(pane_id: str, title: str, terminal_text: str):
    log(f"[{title} | {pane_id}] Handling BLOCKED state...")
    lower = terminal_text.lower()

    # Interactive choice questionnaire (AskUserQuestion TUI)
    if any(m in terminal_text for m in ["?", ">", "Review your answers", "Ready to submit", "Enter to select"]) or "select" in lower:
        log(f"[{title} | {pane_id}] Detected interactive selector/question. Sending Enter to select default/recommended...")
        run_cmd([HERDR, "pane", "send-keys", pane_id, "Enter"])
        time.sleep(2)
        term_after = get_recent_terminal(pane_id, lines=20)
        # If there is a second question or submit prompt
        if any(m in term_after for m in ["?", ">", "Review your answers", "Ready to submit"]) or "submit" in term_after.lower():
            log(f"[{title} | {pane_id}] Sending subsequent Enter to confirm/submit...")
            run_cmd([HERDR, "pane", "send-keys", pane_id, "Enter"])
        return

    # Yes/No prompt
    if any(m in lower for m in ["(y/n)", "[y/n]", "continue?"]):
        log(f"[{title} | {pane_id}] Detected yes/no prompt. Sending 'y' + Enter...")
        run_cmd([HERDR, "pane", "send-text", pane_id, "y\n"])
        return

    # Generic Enter to clear any blocking prompt
    log(f"[{title} | {pane_id}] Sending Enter keypress to unblock...")
    run_cmd([HERDR, "pane", "send-keys", pane_id, "Enter"])

def main():
    log("=== Multi-Session Autonomous Supervisor started ===")
    state_tracker = {}  # pane_id -> {"last_terminal": "", "idle_ticks": 0}

    while True:
        agents = list_claude_agents()
        if not agents:
            log("No active Claude agents found. Retrying in 10s...")
            time.sleep(10)
            continue

        for ag in agents:
            pane_id = ag["pane_id"]
            status = ag["status"]
            cwd = ag["cwd"]
            title = ag["title"] or os.path.basename(cwd)

            if pane_id not in state_tracker:
                state_tracker[pane_id] = {"last_terminal": "", "idle_ticks": 0}

            tracker = state_tracker[pane_id]

            if status == "working":
                tracker["idle_ticks"] = 0
                continue

            terminal = get_recent_terminal(pane_id, lines=30)

            if status == "blocked":
                log(f"[{title} | {pane_id}] Status is 'blocked'.")
                handle_blocked_agent(pane_id, title, terminal)
                time.sleep(2)
                continue

            if status == "idle":
                # Check if terminal text changed
                if terminal == tracker["last_terminal"]:
                    tracker["idle_ticks"] += 1
                    if tracker["idle_ticks"] > 2:  # idle for >20-30s
                        log(f"[{title} | {pane_id}] Idle for >30s. Sending continuation prompt...")
                        prompt_text = generate_continuation_prompt(cwd, terminal)
                        res = run_cmd([HERDR, "agent", "prompt", pane_id, prompt_text])
                        if "error" in res.lower() or "rejected" in res.lower():
                            run_cmd([HERDR, "pane", "send-text", pane_id, prompt_text + "\n"])
                        tracker["last_terminal"] = ""
                        tracker["idle_ticks"] = 0
                        time.sleep(5)
                else:
                    tracker["last_terminal"] = terminal
                    reply = generate_continuation_prompt(cwd, terminal)
                    log(f"[{title} | {pane_id}] Idle with new output. Prompting: {reply[:80]}...")
                    res = run_cmd([HERDR, "agent", "prompt", pane_id, reply])
                    if "error" in res.lower() or "rejected" in res.lower():
                        run_cmd([HERDR, "pane", "send-text", pane_id, reply + "\n"])
                    time.sleep(5)

        time.sleep(5)

if __name__ == "__main__":
    main()
