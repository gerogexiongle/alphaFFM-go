# FFM Field 自动提取机制说明

## 问题

`test_data.txt` 的数据格式是 FM 格式（没有明确的 field 信息），为什么在 FFM 中也能正常工作？

```
1 sex:1 age:0.3 f1:1 f3:0.9
0 sex:0 age:0.7 f2:0.4 f5:0.8 f8:1
```

## 答案：自动 Field 提取

alphaFFM-go 实现了**智能的 field 自动提取**机制，支持两种数据格式：

### 格式 1：显式 Field（推荐用于生产环境）

```
label field:feature:value field:feature:value ...
```

例如：
```
1 user:u123:1 item:i456:1 price:p1:0.5 category:electronics:1
```

这种格式明确指定了每个特征的 field，FFM 可以精确建模不同 field 之间的交互。

### 格式 2：自动提取 Field（兼容 FM 格式）

```
label feature:value feature:value ...
```

例如：
```
1 sex:1 age:0.3 f1:1 f3:0.9
```

当使用这种格式时，FFM 会**自动从特征名提取 field 名称**。

## Field 提取规则

代码位置：`pkg/sample/sample.go` 中的 `extractFieldFromFeature` 函数

```go
func extractFieldFromFeature(feature string) string {
    // 规则1: 按下划线分割
    // user_123 -> field = "user"
    parts := strings.Split(feature, "_")
    if len(parts) > 1 {
        return parts[0]
    }
    
    // 规则2: 按数字分割
    // f1, f2, f3 -> field = "f"
    // age123 -> field = "age"
    for i, ch := range feature {
        if ch >= '0' && ch <= '9' {
            if i > 0 {
                return feature[:i]  // 返回数字前的部分
            }
            break
        }
    }
    
    // 规则3: 默认使用整个特征名作为field
    // sex -> field = "sex"
    // age -> field = "age"
    return feature
}
```

## test_data.txt 的 Field 提取结果

原始数据：
```
1 sex:1 age:0.3 f1:1 f3:0.9
```

提取结果：
- `sex` → field = **`sex`** (规则3：整个特征名)
- `age` → field = **`age`** (规则3：整个特征名)
- `f1` → field = **`f`** (规则2：数字前的部分)
- `f3` → field = **`f`** (规则2：数字前的部分)
- `f2` → field = **`f`** (规则2：数字前的部分)
- `f5` → field = **`f`** (规则2：数字前的部分)
- `f8` → field = **`f`** (规则2：数字前的部分)

最终提取的 field 列表：**`sex`, `age`, `f`**

这可以从模型文件第一行验证：
```bash
$ head -1 model.txt
FIELDS sex age f
```

## FFM 如何使用这些 Field

假设一个样本：`1 sex:1 f1:0.5 f2:0.3`

提取的 field：
- `sex` → field = `sex`
- `f1` → field = `f`
- `f2` → field = `f`

FFM 会为每个特征维护针对其他 field 的隐向量：

```
特征 sex:
  - v_sex,f  (针对 field "f" 的隐向量)
  
特征 f1:
  - v_f1,sex (针对 field "sex" 的隐向量)
  - v_f1,f   (针对 field "f" 的隐向量)
  
特征 f2:
  - v_f2,sex (针对 field "sex" 的隐向量)
  - v_f2,f   (针对 field "f" 的隐向量)
```

预测时的特征交互：
```
交互1: sex × f1
  内积 = <v_sex,f, v_f1,sex>
  
交互2: sex × f2
  内积 = <v_sex,f, v_f2,sex>
  
交互3: f1 × f2
  内积 = <v_f1,f, v_f2,f>
```

## 提取示例

### 示例 1：下划线分割
```
特征名: user_id_123
提取 field: "user"
```

### 示例 2：数字分割
```
特征名: item1
提取 field: "item"

特征名: category9
提取 field: "category"

特征名: f100
提取 field: "f"
```

### 示例 3：纯字母
```
特征名: gender
提取 field: "gender"

特征名: location
提取 field: "location"
```

### 示例 4：数字开头（退化情况）
```
特征名: 123abc
提取 field: "123abc"  (整个特征名，因为数字在第0位)
```

## 为什么这样设计？

### 优点
1. **向后兼容**：可以直接使用 FM 格式的数据
2. **自动化**：不需要手动标注 field
3. **灵活性**：支持多种命名规范

### 局限性
1. **不够精确**：自动提取可能不如显式指定准确
2. **依赖命名规范**：特征名需要遵循一定规则

### 最佳实践

**生产环境推荐使用显式 field 格式**：
```
# 好的做法 - 显式指定 field
1 user:u123:1 item:i456:1 price:high:1 category:electronics:1

# 可以工作，但不够精确
1 user_123:1 item_456:1 price_high:1 category_electronics:1

# 可以工作，但 field 会被合并
1 u123:1 i456:1 price1:1 category1:1
```

## 实际效果验证

运行以下命令查看自动提取的 field：

```bash
# 训练模型
cat test_data.txt | ./bin/ffm_train -m model.txt -dim 1,1,4 -core 1

# 查看提取的 field（模型文件第一行）
head -1 model.txt
# 输出: FIELDS sex age f
```

特征 `sex`, `age` 各自是一个 field，而 `f1, f2, f3, f5, f8` 都属于 field `f`。

## 总结

alphaFFM-go 的智能 field 提取机制使得：
1. ✅ 可以直接使用 FM 格式的数据
2. ✅ FFM 仍然能发挥 field-aware 的优势
3. ✅ 对于命名规范的特征（如 f1, f2, f3），会自动归类到同一个 field
4. ⚠️ 但效果可能不如显式指定 field 的数据格式

**建议**：
- 学习和测试阶段：使用自动提取，方便快捷
- 生产环境：使用显式 field 格式，效果更好

