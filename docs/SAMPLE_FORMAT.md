# FFM 样本格式完整说明

## 三种样本格式支持

alphaFFM-go 支持三种样本格式，每种格式的域映射规则不同：

---

## 格式1: 显式域名（FFM格式）

### 格式
```
label field:feature:value field:feature:value ...
```

### 示例
```
1 user:sex:1 user:age:0.3 item:f1:1 item:f3:0.9
0 user:u123:1 item:i456:1 price:p1:0.5
```

### 特点
- ✅ 域名直接在样本中指定
- ✅ 不需要配置文件
- ✅ 完全控制，灵活性最高
- ❌ 样本文件体积较大

### 使用场景
适合域名复杂、不规则的场景

---

## 格式2: 隐式域名 + 配置文件（字符串/小数字特征）

### 格式
```
label feature:value feature:value ...
```

### 特征类型
- 字符串特征：`sex`, `age`, `f1`, `user_id` 等
- 小数字特征：`1`, `64`, `999` 等（< 1000000）

### 规则
⚠️ **必须在配置文件中定义映射，否则报错**

### 配置文件示例
```
# field_config.txt
sex user
age user
f1 item
f2 item
64 other
```

### 样本示例
```
1 sex:1 age:0.3 f1:1 f2:0.4
0 sex:0 age:0.7 64:1
```

### 错误示例
```
1 sex:1 unknown_feature:1  # 错误！unknown_feature 不在配置中
```

错误信息：
```
Warning: skip invalid sample: failed to get field for feature: 
feature 'unknown_feature' not found in config and not a large numeric feature (>= 1000000)
```

### 使用场景
适合特征名规范、域划分明确的场景

---

## 格式3: 隐式域名 + 自动提取（大数字特征）

### 格式
```
label feature:value feature:value ...
```

### 特征类型
大数字特征（>= 1000000），遵循特殊编码规范：
- **高32位** = 域ID
- **低32位** = 特征ID

### 编码规则
```
特征编码 = (域ID << 32) | 特征ID
```

### 示例解析

| 特征值 | 十六进制 | 域ID (高32位) | 特征ID (低32位) | 自动域名 |
|--------|----------|---------------|-----------------|----------|
| 51539607553 | 0x0000000C00000001 | 12 | 1 | field_12 |
| 55834574849 | 0x0000000D00000001 | 13 | 1 | field_13 |
| 60129542145 | 0x0000000E00000001 | 14 | 1 | field_14 |
| 999 | 0x00000000000003E7 | 0 | 999 | 需要配置 |

### 规则
✅ **自动提取高32位作为域ID，不需要配置，不报错**

### 样本示例
```
1 51539607553:1 55834574849:1 60129542145:0.5
0 51539607554:1 55834574850:1
```

### 生成的域名
- `51539607553` → `field_12`
- `55834574849` → `field_13`
- `60129542145` → `field_14`

### 使用场景
适合大规模特征、域ID通过编码固化的场景（推荐）

---

## 混合格式（推荐）

可以在同一样本中混用格式2和格式3：

### 样本示例
```
1 51539607553:1 55834574849:1 60129542145:0.5 sex:1 age:0.3
0 51539607554:1 55834574850:1 f1:1 f2:0.4
```

### 配置文件（只配置小特征）
```
# field_config.txt
sex user
age user
f1 item
f2 item
```

### 处理逻辑
1. `51539607553`, `55834574849`, `60129542145` → 大数字，自动提取 → `field_12`, `field_13`, `field_14`
2. `sex`, `age`, `f1`, `f2` → 小特征，配置映射 → `user`, `item`

### 最终域列表
```
FIELDS field_12 field_13 field_14 user item
```

### 优势
- ✅ 大数字特征无需配置，自动处理
- ✅ 小特征灵活配置
- ✅ 样本文件简洁
- ✅ 支持海量域（2^32 个）

---

## 使用方法

### 训练
```bash
# 格式1: 显式域名（不需要配置文件）
cat data_explicit.txt | ./bin/ffm_train -m model.txt -dim 1,1,8

# 格式2+3: 隐式域名（需要配置文件）
cat data_implicit.txt | ./bin/ffm_train \
    -m model.txt \
    -field_config field_config.txt \
    -dim 1,1,8
```

### 预测
```bash
# 必须使用与训练时相同的配置
cat test.txt | ./bin/ffm_predict \
    -m model.txt \
    -field_config field_config.txt \
    -dim 8 \
    -out predictions.txt
```

---

## 配置文件格式

### 文本格式（推荐）
```
# 注释行
feature_prefix field_name

# 示例
sex user
age user
f1 item
64 other
```

### JSON格式
```json
{
  "mode": "config",
  "use_prefix": true,
  "default_field": "",
  "numeric_field_threshold": 1000000,
  "numeric_field_prefix": "field_",
  "feature_to_field": {
    "sex": "user",
    "age": "user",
    "f1": "item",
    "f2": "item"
  }
}
```

### 参数说明
- `mode`: 模式，建议设置为 `config`
- `use_prefix`: 是否前缀匹配（true: `user_` 匹配所有 `user_*`）
- `default_field`: 默认域名（为空时，未匹配特征会报错）
- `numeric_field_threshold`: 数字特征阈值（默认 1000000）
- `numeric_field_prefix`: 数字域前缀（默认 `field_`）

---

## 错误处理

### 1. 小特征未配置
```
样本: 1 sex:1 unknown:1
错误: feature 'unknown' not found in config and not a large numeric feature
```
**解决**: 在配置文件中添加 `unknown` 的映射

### 2. 配置文件格式错误
```
错误: invalid format at line 5: expected 'feature field'
```
**解决**: 检查配置文件格式，每行应为 `feature field`

### 3. 训练和预测配置不一致
```
错误: field mismatch between model and config
```
**解决**: 训练和预测必须使用相同的配置文件

---

## 最佳实践

### 1. 选择合适的格式
- **大规模业务特征**: 使用格式3（大数字编码）
- **小规模自定义特征**: 使用格式2（配置文件）
- **混合场景**: 使用混合格式（推荐）

### 2. 配置文件管理
- 将配置文件与模型一起保存
- 使用版本控制管理配置变更
- 添加注释说明每个域的含义

### 3. 特征编码规范
- 大数字特征：使用高32位编码域ID
- 小特征：使用有意义的命名（如 `user_id`, `item_category`）
- 阈值设置：根据业务实际情况调整（默认 1000000）

### 4. 错误排查
- 查看训练/预测日志中的 Warning 信息
- 检查配置文件是否包含所有小特征
- 验证大数字特征是否 >= 阈值

---

## 示例脚本

项目提供了完整的示例脚本：

1. `example_with_config.sh` - 配置文件模式示例
2. `example_numeric_field.sh` - 数字特征自动提取示例
3. `test_three_modes.sh` - 三种格式完整测试

运行示例：
```bash
./example_numeric_field.sh
```

