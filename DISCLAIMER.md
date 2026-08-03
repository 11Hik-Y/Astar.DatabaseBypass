# Disclaimer

Copyright © 2026 Astar.

## Purpose and behavior

Astar.DatabaseBypass only bypasses the official SPT database hash consistency check during database import.

The mod does not write, modify, delete, repair, migrate, or validate database files. It also does not write, modify, delete, repair, migrate, or validate player profile files.

The mod changes only the in-memory verification path for the current server process. SPT continues to perform its normal database reading, JSON parsing, deserialization, and error handling. Invalid JSON, incompatible data, missing references, and other database errors may still prevent startup or cause runtime failures.

## User responsibility

Any custom database edit, third-party database edit, converted database, unsupported content, or conflicting mod is used entirely at the user's own risk.

By installing or using this mod, the user accepts responsibility for evaluating the validity, compatibility, and consequences of their own modifications and any third-party modifications.

The author is not responsible for startup failures, runtime errors, data conflicts, mod conflicts, corrupted or incompatible custom data, profile problems caused by custom data, or any other consequence caused by user or third-party modifications.

Keeping recoverable copies of important database and profile data is recommended, but it is not a mandatory installation condition imposed by this mod.

## No warranty

To the maximum extent permitted by applicable law, this project is provided "as is" and "as available", without warranties or representations of any kind, express, implied, statutory, or otherwise.

The author does not guarantee compatibility with every SPT patch, database modification, third-party mod, operating environment, or future server release.

## Limitation of liability

To the maximum extent permitted by applicable law, the author shall not be liable for any direct, indirect, incidental, special, consequential, exemplary, or other loss, cost, expense, or damage arising from the use, inability to use, redistribution, modification, or combination of this project with user-created or third-party content.

## License and redistribution

The original material in this project is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International Public License.

SPDX identifier: `CC-BY-NC-SA-4.0`

Canonical license URI:

```text
https://creativecommons.org/licenses/by-nc-sa/4.0/
```

Redistribution and adapted versions must comply with the attribution, noncommercial, and ShareAlike conditions of that license. Commercial use requires separate permission from the copyright holder.

## Third-party rights

This project is an independent community project. It is not affiliated with, endorsed by, or sponsored by Battlestate Games or the SPT project.

SPT, Escape from Tarkov, and all referenced third-party components remain subject to their respective owners' licenses, trademarks, and other rights.
