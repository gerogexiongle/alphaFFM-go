# FFM Field 提取策略详解

## 核心问题

**问题**：对于 FM 格式的数据（只有特征名，没有显式 field），FFM 如何合理地分配 field？

```
数据示例:
1 sex:1 age:0.3 f1:1 f3:0.9

问题：
- sex, age, f1, f3 都是不同的特征
- 它们没有明确的 field 语义（如 user field, item field）
- FFM 需要 field 信息才能建模
```

## 三种处理策略

### 策略 1：启发式规则（❌ 不推荐 - 已废弃）

**旧实现**：
```go
// 按数字分割: f1, f2, f3 → field = "f"
// 按下划线分割: user_id → field = "user"
// 默认: sex → field = "sex"
```

**问题**：
1. `f1, f2, f3` 是不同特征，却被归为同一个 field `f`
2. `sex, age` 各自独立成 field，语义不一致
3. 缺乏明确的 field 语义，FFM 的优势无法发挥

### 策略 2：每个特征自成一个 field（✅ 当前实现）

**新实现**：
```go
func extractFieldFromFeature(feature string) string {
    // 策略1: 按下划线分割（适用于规范命名）
    // user_id → field = "user"
    parts := strings.Split(feature, "_")
    if len(parts) > 1 {
        return parts[0]
    }
    
    // 策略2: 默认 - 每个特征自成一个field
    // sex → field = "sex"
    // age → field = "age"
    // f1 → field = "f1"
    // f2 → field = "f2"
    return feature
}
```

**效果**：
```
原始数据: 1 sex:1 age:0.3 f1:1 f3:0.9

提取结果:
FIELDS sex age f1 f3 f2 f5 f8

每个特征都是独立的 field
```

**优点**：
- ✅ 逻辑清晰，每个特征语义独立
- ✅ 避免了不合理的 field 合并
- ✅ FFM 仍然是 field-aware 的
- ✅ 效果接近精细版 FM

**缺点**：
- ⚠️ 参数量大幅增加（n 个特征需要 n×n×k 个参数）
- ⚠️ 训练时间增加
- ⚠️ 容易过拟合

### 策略 3：使用显式 field 格式（🎯 最佳实践）

**推荐做法**：
```
# 数据预处理，添加显式 field 信息
1 user:sex:1 user:age:0.3 item:f1:1 item:f3:0.9

提取结果:
FIELDS user item

这才是 FFM 的正确用法！
```

## 实际效果对比

### 测试数据
```
1 sex:1 age:0.3 f1:1 f3:0.9
0 sex:0 age:0.7 f2:0.4 f5:0.8 f8:1
...
```

### 旧策略（启发式规则）
```bash
FIELDS sex age f

模型大小: 2,102 bytes
Field 数量: 3
每个特征的参数: k × 3
```

**问题**：`f1, f2, f3, f5, f8` 被错误地归为同一个 field `f`

### 新策略（每特征一 field）
```bash
FIELDS sex age f1 f3 f2 f5 f8

模型大小: 7,285 bytes
Field 数量: 7
每个特征的参数: k × 7
```

**改进**：每个特征独立，逻辑合理

### 显式 field（最佳）
```bash
# 使用显式 field 数据
1 user:sex:1 user:age:0.3 item:f1:1 item:f3:0.9

FIELDS user item

模型大小: 小且高效
Field 数量: 2（符合业务语义）
每个特征的参数: k × 2
```

**最优**：field 有明确语义，FFM 效果最好

## 参数量对比

假设：
- 特征数量 n = 100
- 隐向量维度 k = 8

| 方法 | Field数 | 每特征参数 | 总参数量 |
|------|---------|------------|----------|
| FM | 1 | 1 + k = 9 | 900 |
| FFM (显式2个field) | 2 | 1 + k×2 = 17 | 1,700 |
| FFM (显式10个field) | 10 | 1 + k×10 = 81 | 8,100 |
| FFM (每特征1个field) | 100 | 1 + k×100 = 801 | 80,100 |

**结论**：每特征一个 field 会导致**参数量爆炸**！

## 使用建议

### 场景 1：学习和测试（可以用当前策略）

```bash
# 使用 FM 格式数据，自动提取 field
cat test_data.txt | ./bin/ffm_train -m model.txt -dim 1,1,4 -core 1

# 每个特征自成一个 field
# 适合小规模数据测试
```

**适用条件**：
- 特征数量少（< 50）
- 数据量小（用于学习和测试）
- 不在乎模型大小

### 场景 2：生产环境（必须用显式 field）

```bash
# 数据预处理：添加 field 信息
# 原始数据
1 sex:1 age:0.3 category:electronics:1 price:100:1

# 预处理后（添加 field）
1 user:sex:1 user:age:0.3 item:category:electronics:1 item:price:100:1

# 训练
cat processed_data.txt | ./bin/ffm_train -m model.txt -dim 1,1,8 -core 4
```

**为什么必须这样做**：
1. **控制参数量**：field 数量可控
2. **业务语义**：field 有明确含义
3. **效果更好**：FFM 能正确建模 field 间交互
4. **训练更快**：参数量小，收敛快

## 数据预处理建议

### Python 预处理脚本

```python
# add_field_info.py
import sys

# 定义特征到 field 的映射
FEATURE_TO_FIELD = {
    'sex': 'user',
    'age': 'user',
    'user_id': 'user',
    'category': 'item',
    'item_id': 'item',
    'price': 'item',
    'hour': 'context',
    'weekday': 'context',
}

def add_field_info(line):
    parts = line.strip().split()
    label = parts[0]
    features = parts[1:]
    
    result = [label]
    for feat in features:
        if ':' in feat:
            feat_name, feat_val = feat.split(':', 1)
            # 查找 field
            field = FEATURE_TO_FIELD.get(feat_name, 'other')
            # 输出: field:feature:value
            result.append(f"{field}:{feat_name}:{feat_val}")
    
    return ' '.join(result)

# 处理输入
for line in sys.stdin:
    print(add_field_info(line))
```

使用：
```bash
cat original_data.txt | python add_field_info.py > processed_data.txt
```

### Shell 简单处理

```bash
# 假设规则：user_ 开头的是 user field，item_ 开头的是 item field
cat data.txt | sed 's/\buser_\([^:]*\):/user:user_\1:/g' | \
               sed 's/\bitem_\([^:]*\):/item:item_\1:/g' > processed.txt
```

## 命名规范建议

如果使用自动提取，建议遵循以下规范：

### 推荐：下划线前缀表示 field

```
原始特征名:
user_id, user_age, user_gender
item_id, item_category, item_price
context_hour, context_weekday

自动提取结果:
user_id → field = "user"
item_category → field = "item"
context_hour → field = "context"

效果: 符合预期！
```

### 不推荐：无语义命名

```
原始特征名:
f1, f2, f3, sex, age

自动提取结果（旧策略）:
f1, f2, f3 → field = "f"  ❌ 错误归类
sex → field = "sex"       ❌ 过于细粒度
age → field = "age"       ❌ 过于细粒度

自动提取结果（新策略）:
每个特征独立 field      ⚠️ 参数量大
```

## 总结

### 问题本质

FFM 需要**明确的 field 语义**才能发挥优势。对于没有 field 信息的数据：
- 旧策略（启发式规则）：会产生**逻辑错误**
- 新策略（每特征一 field）：逻辑正确但**参数量爆炸**
- 最佳策略（显式 field）：需要**数据预处理**

### 选择建议

| 场景 | 推荐策略 | 说明 |
|------|----------|------|
| 学习测试（小数据） | 新策略（自动提取） | 可以接受参数量增加 |
| 生产环境（大数据） | 显式 field | 必须预处理数据 |
| 有命名规范 | 自动提取（下划线） | user_id → user |
| 无命名规范 | 先用 FM | FFM 优势无法发挥 |

### 代码已更新

当前实现（`pkg/sample/sample.go`）：
1. ✅ 优先识别下划线规范（`user_id` → `user`）
2. ✅ 默认每个特征独立（`sex` → `sex`）
3. ❌ 移除了错误的数字分割规则

这样既保证了逻辑正确性，又为生产环境提供了明确的最佳实践指引。

