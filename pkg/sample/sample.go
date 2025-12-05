package sample

import (
	"fmt"
	"strconv"
	"strings"
)

// FFMSample FFM样本数据结构
type FFMSample struct {
	Y int                         // 标签: 1 或 -1
	X []FeatureValue              // 特征列表
}

// FeatureValue FFM特征和值（包含field信息）
type FeatureValue struct {
	Field   string  // field名称（用于FFM的field-aware）
	Feature string  // 特征名称
	Value   float64 // 特征值
}

// ParseSample 解析样本字符串
// 格式: label field1:feature1:value1 field2:feature2:value2 ...
// 例如: 1 user:u123:1 item:i456:1 price:p1:0.5
func ParseSample(line string) (*FFMSample, error) {
	parts := strings.Fields(line)
	if len(parts) == 0 {
		return nil, fmt.Errorf("empty line")
	}

	sample := &FFMSample{
		X: make([]FeatureValue, 0),
	}

	// 解析标签
	label, err := strconv.Atoi(parts[0])
	if err != nil {
		return nil, fmt.Errorf("invalid label: %v", err)
	}
	if label > 0 {
		sample.Y = 1
	} else {
		sample.Y = -1
	}

	// 解析特征
	// 支持两种格式:
	// 1. field:feature:value (FFM格式)
	// 2. feature:value (FM格式，自动从feature名提取field)
	for i := 1; i < len(parts); i++ {
		kv := strings.Split(parts[i], ":")
		
		var field, feature string
		var value float64
		
		if len(kv) == 3 {
			// FFM格式: field:feature:value
			field = kv[0]
			feature = kv[1]
			value, err = strconv.ParseFloat(kv[2], 64)
			if err != nil {
				return nil, fmt.Errorf("invalid feature value: %v", err)
			}
		} else if len(kv) == 2 {
			// FM格式: feature:value，从feature名提取field
			feature = kv[0]
			// 提取field：如果feature包含下划线或其他分隔符，取第一部分作为field
			// 例如: sex_male -> field=sex, feature=sex_male
			field = extractFieldFromFeature(feature)
			value, err = strconv.ParseFloat(kv[1], 64)
			if err != nil {
				return nil, fmt.Errorf("invalid feature value: %v", err)
			}
		} else {
			return nil, fmt.Errorf("invalid feature format: %s", parts[i])
		}

		// 跳过值为0的特征
		if value != 0 {
			sample.X = append(sample.X, FeatureValue{
				Field:   field,
				Feature: feature,
				Value:   value,
			})
		}
	}

	return sample, nil
}

// extractFieldFromFeature 从特征名提取field名
func extractFieldFromFeature(feature string) string {
	// 策略1: 按下划线分割（推荐的命名规范）
	// 例如: user_id, user_age, item_category 等
	// user_id → field = "user"
	parts := strings.Split(feature, "_")
	if len(parts) > 1 {
		return parts[0]
	}
	
	// 策略2: 按驼峰命名分割（可选）
	// 例如: userId, userAge → field = "user"
	// 这里暂不实现，因为可能产生歧义
	
	// 策略3: 默认 - 每个特征自成一个field
	// 这样做的好处：
	// 1. 对于无法识别的特征（如 sex, age, f1），每个特征有独立的field语义
	// 2. FFM 仍然是 field-aware 的，只是 field 粒度更细
	// 3. 效果接近 FM，但保持了 FFM 的建模能力
	//
	// 注意：这种情况下，FFM 的参数量会显著增加
	// 如果有 n 个特征，每个特征需要维护 n 个隐向量（针对其他 n-1 个特征的field）
	return feature
}

