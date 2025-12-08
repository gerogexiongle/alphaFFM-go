# 为什么 scripts/demo.sh 能成功（没有显式指定域名）？

## 回答

`scripts/demo.sh` 能成功运行是因为它**没有使用配置文件**，走的是 **Auto 模式**。

## 详细说明

### 1. 查看命令
```bash
cat test_data.txt | ./bin/ffm_train -m demo_model.txt -dim 1,1,4 -core 1
```
**注意**: 没有 `-field_config` 参数！

### 2. 样本内容
```
1 sex:1 age:0.3 f1:1 f3:0.9
0 sex:0 age:0.7 f2:0.4 f5:0.8 f8:1
```
- 格式: `label feature:value`
- 特征: `sex`, `age`, `f1`, `f2`, `f3`, `f5`, `f8` (都是字符串)

### 3. 处理逻辑

当**没有配置文件**时，系统使用 **Auto 模式**：

```
Auto 模式规则：
1. 如果特征名包含下划线，提取第一部分作为域名
   例如: user_id → field = "user"
   
2. 否则，特征名本身作为域名
   例如: sex → field = "sex"
        age → field = "age"
        f1 → field = "f1"
```

### 4. 生成的域

查看模型文件第一行：
```
FIELDS sex age f1 f3 f2 f5 f8
```

每个特征都成为独立的域！

### 5. 三种模式对比

| 模式 | 触发条件 | 小特征处理 | 大数字特征 |
|------|---------|-----------|----------|
| **Auto** | 无配置文件 | 自动提取，不报错 | 自动提取高32位 |
| **Config** | 有配置文件 | **必须配置，否则报错** | 自动提取高32位 |
| **Explicit** | 样本显式指定 | 使用样本中的域名 | 使用样本中的域名 |

---

## 对比示例

### 示例1: Auto 模式（无配置文件）
```bash
# 命令
cat test_data.txt | ./bin/ffm_train -m model.txt -dim 1,1,4

# 样本
1 sex:1 age:0.3 f1:1

# 结果
✅ 成功！
FIELDS sex age f1
```

### 示例2: Config 模式（有配置文件）
```bash
# 命令
cat test_data.txt | ./bin/ffm_train -m model.txt -field_config config.txt -dim 1,1,4

# 样本
1 sex:1 age:0.3 unknown:1

# 配置文件只有
sex user
age user

# 结果
❌ 报错！
Warning: skip invalid sample: feature 'unknown' not found in config
```

### 示例3: Config 模式 + 大数字（有配置文件）
```bash
# 命令
cat test_data.txt | ./bin/ffm_train -m model.txt -field_config config.txt -dim 1,1,4

# 样本
1 51539607553:1 55834574849:1 sex:1 age:0.3

# 配置文件
sex user
age user

# 结果
✅ 成功！
FIELDS field_12 field_13 user
# 51539607553 → field_12 (自动提取，不需要配置)
# sex, age → user (配置映射)
```

---

## 总结

| 场景 | 配置文件 | 小特征行为 | 适用情况 |
|------|---------|-----------|---------|
| `scripts/demo.sh` | ❌ 无 | 每个特征独立域 | 快速测试、小数据集 |
| 生产环境 | ✅ 有 | 严格检查，减少域数量 | 正式训练、大规模数据 |

**建议**:
- 测试/演示: 可以不用配置文件（Auto 模式）
- 生产环境: 必须使用配置文件（Config 模式），严格控制域映射

