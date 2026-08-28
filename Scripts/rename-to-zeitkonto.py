# -*- coding: utf-8 -*-
"""
Rename the product from Hours to Zeitkonto.

Whole strings, never substrings: "Hours" is also the plain English noun, and
"Hours and balance", "Hours per day" and "Hours you enter in the calendar"
must survive untouched. Every replacement below was read in context first.
"""
import json, pathlib, re, sys

OLD, NEW = "Hours", "Zeitkonto"

# Full literals whose "Hours" is the product. Anything not listed is the noun.
STRINGS = {
 "Hours Pro": "Zeitkonto Pro",
 "Buying Hours Pro": "Buying Zeitkonto Pro",
 "Unlock Hours Pro": "Unlock Zeitkonto Pro",
 "Widgets are part of Hours Pro": "Widgets are part of Zeitkonto Pro",
 "Everything Hours can do": "Everything Zeitkonto can do",
 "Open Hours": "Open Zeitkonto",
 "Open Hours once to fill this in": "Open Zeitkonto once to fill this in",
 "A second job is part of Hours Pro. The job you have keeps working either way.":
   "A second job is part of Zeitkonto Pro. The job you have keeps working either way.",
 "A subscription renews until you cancel it, in Settings › your name › Subscriptions. Buying Hours outright is a single payment and never renews.":
   "A subscription renews until you cancel it, in Settings › your name › Subscriptions. Buying Zeitkonto outright is a single payment and never renews.",
 "Nothing to restore on this Apple ID. If you bought Hours with a different one, sign in with that one and try again.":
   "Nothing to restore on this Apple ID. If you bought Zeitkonto with a different one, sign in with that one and try again.",
 "Notifications are switched off for Hours in the Settings app. Turn them on there and this will start working.":
   "Notifications are switched off for Zeitkonto in the Settings app. Turn them on there and this will start working.",
 "Payment is handled entirely by the App Store, the way every purchase on your phone is. Hours is told one thing in return — whether it has been paid for — and never sees your name, your email or your card. There is still nothing to sign into.":
   "Payment is handled entirely by the App Store, the way every purchase on your phone is. Zeitkonto is told one thing in return — whether it has been paid for — and never sees your name, your email or your card. There is still nothing to sign into.",
 "Sync starts the next time you open Hours.": "Sync starts the next time you open Zeitkonto.",
 "Sync stops the next time you open Hours.": "Sync stops the next time you open Zeitkonto.",
 "That purchase is waiting for approval. Hours will open up on its own once it goes through.":
   "That purchase is waiting for approval. Zeitkonto will open up on its own once it goes through.",
 "The one thing it asks the network is whether Hours Pro has been paid for, which it asks the App Store; no part of your hours goes with the question.":
   "The one thing it asks the network is whether Zeitkonto Pro has been paid for, which it asks the App Store; no part of your hours goes with the question.",
 "This backup was made by a newer version of Hours (format \\(version)). Update Hours and try again.":
   "This backup was made by a newer version of Zeitkonto (format \\(version)). Update Zeitkonto and try again.",
 "This file is not a Hours backup.": "This file is not a Zeitkonto backup.",
 "Timesheets are part of Hours Pro. Settings › Backup and data writes a file with every day you have ever recorded in it, and always will, free.":
   "Timesheets are part of Zeitkonto Pro. Settings › Backup and data writes a file with every day you have ever recorded in it, and always will, free.",
 "Hours backup \\(stamp).json": "Zeitkonto backup \\(stamp).json",
}

# The plain noun. Listed so the intent is on the record, and so a future
# reader can see these were considered rather than missed.
LEFT_ALONE = [
 "Hours and balance", "Hours per day", "Hours worked per day",
 "Hours worked this month, and whether you are ahead or behind.",
 "Hours you enter in the calendar appear here.",
 "Hours already recorded against this job stay, and count towards \\(settingsStore.settings.primaryJob.name).",
 "A summary, then the days, then their totals. Hours read as 8h 00m and still add up.",
 "Hours",  # the metric label beside a time range; the noun, in DaySummaryCard
]

def swift_files():
    for root in ("Hours", "HoursWidget", "HoursShared", "HoursCore", "HoursTests", "HoursUITests"):
        yield from pathlib.Path(root).rglob("*.swift")

def rewrite(text):
    changed = 0
    for old, new in STRINGS.items():
        needle = f'"{old}"'
        if needle in text:
            changed += text.count(needle)
            text = text.replace(needle, f'"{new}"')
    return text, changed

if __name__ == "__main__":
    total = 0
    for path in swift_files():
        source = path.read_text()
        updated, n = rewrite(source)
        if n:
            path.write_text(updated)
            total += n
            print(f"  {path}: {n}")
    print(f"{total} product-name strings renamed in Swift")
