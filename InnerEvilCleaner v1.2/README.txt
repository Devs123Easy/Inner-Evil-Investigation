Version 1.2

InnerEvil / Exastealer Cleaner

FILES
- Run_InnerEvilCleaner.bat
- InnerEvilCleaner.ps1

USAGE
1. Disconnect the infected computer from the Internet.
2. Copy both files into the same folder.
3. Right-click Run_InnerEvilCleaner.bat and choose "Run as administrator".
4. Choose Quarantine unless permanent deletion is specifically required.
5. Review the report folder created on the Desktop.

WHAT IT DOES
- Stops only processes whose path or command line matches known InnerEvil/Exastealer indicators.
- Removes exact Startup VBS artifacts and suspicious Startup scripts containing known markers.
- Removes exact known files/directories.
- Checks Run/RunOnce registry values, scheduled tasks, and services for known indicators.
- Exports known registry keys before removing them.
- Checks Discord core index.js files for confirmed injection markers.
- Blocks 40.76.119.174 in Windows Firewall and iloveanimals.life in hosts.
- Starts a Microsoft Defender quick scan when available.
- Writes a detailed log and final report.

LIMITATIONS
- It cannot recover or revoke stolen credentials, cookies, tokens, 2FA backup codes, wallet seeds, or payment data.
- It cannot guarantee that every modified or downloaded component has been found.
- A clean reinstall of Windows remains the highest-assurance remediation after execution of a stealer/RAT.
- Password changes and session revocation must be performed from a separate trusted device.

V1.2 fixes malformed multi-line .exename markers, non-executable scheduled task actions, and Defender error reporting.
