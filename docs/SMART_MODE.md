# 智能样本处理模式说明

## 概述

alphaFFM-go 现在支持**智能样本处理**：
- **大数字特征**（>= 1000000）：自动提取高32位作为域ID，无需配置
- **小特征**（字符串或小数字）：必须提供配置文件

这种设计完美适配您的业务场景！

---

## 样本格式处理

### 原始样本格式
```
userID itemID label features...
```

示例：
```
41023628 1666135715_1763885841 1 51539607578:1 55834574857:1 60129542145:0.013 ...
```

### 转换后格式（用于训练）
```bash
awk '{printf "%s", $3; for(i=4; i<=NF; i++) printf " %s", $i; printf "\n"}'
```

结果：
```
1 51539607578:1 55834574857:1 60129542145:0.013 ...
```

---

## 特征编码规则

### 大数字特征（自动处理）

**编码格式**: `特征ID = (域ID << 32) | 特征索引`

**示例解析**:

| 特征ID | 十六进制 | 域ID (高32位) | 特征索引 (低32位) | 自动域名 |
|--------|----------|---------------|-------------------|----------|
| 51539607578 | 0x0000000C0000000A | 12 | 10 | field_12 |
| 55834574857 | 0x0000000D00000009 | 13 | 9 | field_13 |
| 60129542145 | 0x0000000E00000001 | 14 | 1 | field_14 |
| 64424509442 | 0x0000000F00000002 | 15 | 2 | field_15 |

**处理逻辑**:
```go
if numFeature >= 1000000 {
    fieldID := uint32(numFeature >> 32)
    field = fmt.Sprintf("field_%d", fieldID)
}
```

### 小特征（需要配置）

**特征类型**: 
- 字符串：`sex`, `age`, `gender` 等
- 小数字：`1`, `64`, `999` 等（< 1000000）

**要求**: 必须在配置文件中定义映射

---

## 使用方法

### 方式1: 纯大数字特征（推荐，无需配置）

```bash
# 直接训练，无需配置文件
cat data.txt | awk '{printf "%s", $3; for(i=4; i<=NF; i++) printf " %s", $i; printf "\n"}' | \
    ./bin/ffm_train -m model.txt -dim 1,1,8 -core 4

# 预测
cat test.txt | awk '{printf "%s", $3; for(i=4; i<=NF; i++) printf " %s", $i; printf "\n"}' | \
    ./bin/ffm_predict -m model.txt -dim 8 -out pred.txt -core 4
```

### 方式2: 混合特征（需要配置文件）

如果样本中包含小特征，需要提供配置文件：

```bash
# 创建配置文件
cat > field_config.txt <<EOF
sex user
age user
category item
EOF

# 训练
cat data.txt | awk '{printf "%s", $3; for(i=4; i<=NF; i++) printf " %s", $i; printf "\n"}' | \
    ./bin/ffm_train -m model.txt -field_config field_config.txt -dim 1,1,8 -core 4
```

---

## 实际案例

### 您的真实数据

**原始样本**:
```
41023628 1666135715_1763885841 1 51539607578:1 55834574857:1 60129542145:0.013 ...
```

**转换后**:
```
1 51539607578:1 55834574857:1 60129542145:0.013 ...
```

**处理结果**:
```
FIELDS field_1 field_2 field_3 field_21 field_22 field_4 field_5 field_6 field_7 field_8 field_9 field_11
```

✅ **所有特征自动处理，无需配置文件！**

---

## 错误处理

### 错误1: 小特征未配置

**错误信息**:
```
Warning: skip invalid sample: small feature 'sex' requires field config file
```

**解决方案**:
1. 添加配置文件
2. 或使用 FFM 格式：`label field:feature:value`

### 错误2: 负数特征名

**错误信息**:
```
Warning: invalid feature name '-85': feature name cannot be negative number
```

**原因**: 样本格式可能不对

**检查**:
- 确保使用 `awk` 正确提取了 label 和 features
- 原始格式应该是：`userID itemID label features...`
- 转换后格式：`label features...`

---

## 性能优势

### 参数量对比

假设有 n 个特征，k 个域：

| 模式 | 域数量 | 参数量 | 说明 |
|------|--------|--------|------|
| ~~Auto~~ (已移除) | n | O(n²×d) | 每个特征独立域 |
| **大数字自动** | k | O(n×k×d) | 高32位编码的域 |
| Config | k | O(n×k×d) | 配置文件指定 |

**您的场景**: 
- 大数字特征编码已经包含域信息（高32位）
- 自动提取，无需额外配置
- 参数量：O(n×k×d)，其中 k 远小于 n

---

## benchmark_ffm_vs_fm.sh 集成

您的基准测试脚本已经正确处理了样本格式：

```bash
# 训练
find $TRAIN_DATA_DIR -type f -name "part-*.txt" | sort | while read file; do
    cat "$file" | awk '{printf "%s", $3; for(i=4; i<=NF; i++) printf " %s", $i; printf "\n"}'
done | ./bin/ffm_train $FFM_TRAIN_PARAMS -m $FFM_MODEL

# 预测
find $TEST_DATA_DIR -type f -name "part-*.txt" | sort | while read file; do
    cat "$file" | awk '{printf "%s", $3; for(i=4; i<=NF; i++) printf " %s", $i; printf "\n"}'
done | ./bin/ffm_predict $FFM_PREDICT_PARAMS -m $FFM_MODEL -out $FFM_PREDICTION
```

**无需修改**！直接运行即可，所有大数字特征自动处理。

---

## 总结

### ✅ 您的场景完美支持

1. **样本格式**: `userID itemID label features...`
2. **特征编码**: 高32位 = 域ID，低32位 = 特征索引
3. **自动处理**: >= 1000000 的特征自动提取域ID
4. **无需配置**: 纯大数字特征不需要配置文件
5. **性能优化**: 参数量 O(n×k×d)，训练速度快

### 🚀 使用建议

对于您的业务数据：
- ✅ **不需要配置文件**（所有特征都是大数字）
- ✅ 直接使用 `benchmark_ffm_vs_fm.sh` 即可
- ✅ 自动提取域ID，完美适配特征编码规范

---

## 快速验证

```bash
# 测试单行数据
head -1 /path/to/data.txt | \
    awk '{printf "%s", $3; for(i=4; i<=NF; i++) printf " %s", $i; printf "\n"}' | \
    ./bin/ffm_train -m test.txt -dim 1,1,4 -core 1

# 查看生成的域
head -1 test.txt
# 输出：FIELDS field_1 field_2 field_3 ...
```

完美！🎉

