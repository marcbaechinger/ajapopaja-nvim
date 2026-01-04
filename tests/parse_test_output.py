# Copyright (c) 2026 Marc Baechinger
# Licensed under the MIT License.

import re
import sys

# ANSI Color Constants
GREEN = "\033[32m"
RED = "\033[31m"
BOLD = "\033[1m"
RESET = "\033[0m"


def parse_test_output(raw_text):
    # Regex to strip ANSI color codes for logic parsing
    ansi_escape = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")

    # We split the RAW text to preserve colors for the detailed logs
    raw_sections = re.split(r"={10,}", raw_text)

    parsed_sections = []
    total_success = 0
    total_failed = 0
    total_errors = 0

    for raw_section in raw_sections:
        clean_section = ansi_escape.sub("", raw_section)
        if "Testing:" not in clean_section:
            continue

        # Extract filename and stats using the cleaned text
        file_match = re.search(r"Testing:\s+(.*)", clean_section)
        success_match = re.search(r"Success:\s+(\d+)", clean_section)
        failed_match = re.search(r"Failed\s+:\s+(\d+)", clean_section)
        error_match = re.search(r"Errors\s+:\s+(\d+)", clean_section)

        if file_match and success_match:
            filepath = file_match.group(1).strip()
            filename = filepath.split("/")[-1]
            s = int(success_match.group(1))
            f = int(failed_match.group(1))
            e = int(error_match.group(1))

            total_success += s
            total_failed += f
            total_errors += e

            parsed_sections.append(
                {
                    "filename": filename,
                    "success": s,
                    "failed": f,
                    "errors": e,
                    "raw_text": raw_section.strip(),  # Store the colored version
                }
            )

    # --- 1. DETAILED LOGS (Only if there are failures) ---
    has_issues = total_failed > 0 or total_errors > 0

    if has_issues:
        print(f"\n{RED}{BOLD}!!! FAILURE DETAILS !!!{RESET}\n")
        for sec in parsed_sections:
            if sec["failed"] > 0 or sec["errors"] > 0:
                print(f"{BOLD}FILE: {sec['filename']}{RESET}")
                # Print the original raw text (preserves colors)
                print(
                    f"========================================\n{sec['raw_text']}\n========================================\n"
                )

    # --- 2. COLORIZED SUMMARY TABLE ---
    print("\n" + BOLD + "=" * 62 + RESET)
    print(f"{BOLD}{'FILE':<30} | {'SUCCESS':<8} | {'FAILED':<7} | {'ERRORS':<7}{RESET}")
    print("-" * 62)

    for sec in parsed_sections:
        icon = (
            f"{GREEN}✅{RESET}"
            if sec["failed"] == 0 and sec["errors"] == 0
            else f"{RED}❌{RESET}"
        )

        # Colorize numbers based on value
        s_str = (
            f"{GREEN}{sec['success']:<8}{RESET}"
            if sec["success"] > 0
            else f"{sec['success']:<8}"
        )
        f_str = (
            f"{RED}{sec['failed']:<7}{RESET}"
            if sec["failed"] > 0
            else f"{sec['failed']:<7}"
        )
        e_str = (
            f"{RED}{sec['errors']:<7}{RESET}"
            if sec["errors"] > 0
            else f"{sec['errors']:<7}"
        )

        print(f"{icon} {sec['filename']:<27} | {s_str} | {f_str} | {e_str}")

    print("-" * 62)

    # Total row with colors
    total_f_str = (
        f"{RED}{total_failed:<7}{RESET}"
        if total_failed > 0
        else str(total_failed).strip()
    )
    total_e_str = (
        f"{RED}{total_errors:<7}{RESET}"
        if total_errors > 0
        else str(total_errors).strip()
    )

    print(
        f"{BOLD}{'TOTAL':<30}{RESET} | {GREEN}{total_success:<8}{RESET} | {total_f_str:<7} | {total_e_str:<7}"
    )
    print(BOLD + "=" * 62 + RESET)

    if not has_issues:
        print(f"{GREEN}{BOLD}OVERALL STATUS: ALL TESTS PASSED ✅{RESET}")
    else:
        print(
            f"{RED}{BOLD}OVERALL STATUS: {total_failed + total_errors} ISSUE(S) FOUND ❌{RESET}"
        )
    print("\n")


if __name__ == "__main__":
    if not sys.stdin.isatty():
        input_data = sys.stdin.read()
        parse_test_output(input_data)
    else:
        print("Usage: <test_command> | python3 parse_tests.py")
