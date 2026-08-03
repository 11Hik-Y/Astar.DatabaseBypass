# 实现说明

## 为什么使用模块初始化器

SPT 在启动早期扫描 `SPT/user/mods`，加载 DLL 并通过反射实例化 `IModMetadata`。数据库 Hash 加载和数据库导入发生在 Mod Loader 返回之后。因此模块初始化器会在数据库导入前运行。

## 为什么 Patch LoadDatabaseAsync

官方方法接收：

```csharp
Task<DatabaseTables?> LoadDatabaseAsync(
    bool shouldVerifyDatabase,
    CancellationToken cancellationToken = default
)
```

方法内部只有在该参数为 `true` 时才向递归导入器传入 `VerifyDatabaseAsync`。Prefix 将参数改为 `false` 后，官方 JSON 导入代码仍原样执行。

## Fail-closed

如果 SPT 版本变更导致目标方法无法定位，`AbstractPatch.Enable()` 会抛出异常。Mod DLL 加载失败，官方验证路径保持不变。
