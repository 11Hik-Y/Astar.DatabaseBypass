# SPT 4.1.x Runtime 布局

确认日期：2026-08-03

## 实际目录

    <SPT_INSTALL_ROOT>\
    ├─ BepInEx\
    ├─ EscapeFromTarkov_Data\
    ├─ EscapeFromTarkov.exe
    └─ SPT_Runtime\
       ├─ SPT.Server.exe
       ├─ SPT.Server.dll
       ├─ SPT.Launcher.exe
       ├─ SPTarkov.Server.Core.dll
       ├─ SPTarkov.Reflection.dll
       ├─ 0Harmony.dll
       ├─ SPT_Data\
       └─ user\
          └─ mods\

## 开发约束

- SptInstallRoot 指向游戏总根目录。
- SptServerRoot 固定为 $(SptInstallRoot)\SPT_Runtime。
- 服务端 Mod 安装到 SPT_Runtime\user\mods\<ModName>。
- 客户端 Mod 安装到 BepInEx\plugins\<ModName>。
- SPT 4.1.x 不再沿用此前版本的 SPT\... 服务端路径。