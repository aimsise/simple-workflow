---
title: Fix typo in README
findings_version: 1
---

# Findings: Fix typo in README

## Context

README contains a typo in the installation section.

## Investigation Summary

- Line 42 of `README.md` says "npm isntall" instead of "npm install".

## Required Work Units

### 1. Correct README typo

Change "npm isntall" to "npm install" at README.md:42.
Observable: grep -n "npm install" README.md returns line 42.
