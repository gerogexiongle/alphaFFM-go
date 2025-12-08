package main

import (
	"fmt"
)

// ExtractFieldIDFromFeature 从特征ID中提取域ID（高32位）
func ExtractFieldIDFromFeature(featureID uint64) uint32 {
	return uint32(featureID >> 32)
}

func main() {
	// 测试样本中的特征
	features := []uint64{
		51539607553,
		55834574849,
		60129542145,
		64,
	}

	fmt.Println("特征编码解析示例：")
	fmt.Println("==========================================")
	fmt.Println("特征格式：高32位 = 域ID，低32位 = 特征ID")
	fmt.Println("==========================================")
	fmt.Println()

	for _, feature := range features {
		fieldID := ExtractFieldIDFromFeature(feature)
		featureIDLow := uint32(feature & 0xFFFFFFFF)
		
		fmt.Printf("原始特征: %d\n", feature)
		fmt.Printf("  二进制: 0x%016X\n", feature)
		fmt.Printf("  域ID (高32位): %d (0x%08X)\n", fieldID, fieldID)
		fmt.Printf("  特征ID (低32位): %d (0x%08X)\n", featureIDLow, featureIDLow)
		fmt.Printf("  域名: field_%d\n", fieldID)
		fmt.Println()
	}

	fmt.Println("==========================================")
	fmt.Println("使用建议：")
	fmt.Println("  - 特征ID > 4294967296 (2^32) 时自动提取域ID")
	fmt.Println("  - 小特征使用配置文件映射")
	fmt.Println("==========================================")
}

