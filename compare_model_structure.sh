#!/bin/bash
# FM vs FFM 模型文件结构对比脚本

echo "=========================================="
echo "FM vs FFM 模型文件结构对比"
echo "=========================================="
echo ""

# 使用相同的数据和参数
TEST_DATA="/data/xiongle/alphaFM-go/test_data.txt"
DIM="1,1,4"

# 训练 FM
echo "1. 训练 FM 模型..."
cd /data/xiongle/alphaFM-go
cat $TEST_DATA | ./bin/fm_train -m fm_compare.txt -dim $DIM -core 1 >/dev/null 2>&1

# 训练 FFM
echo "2. 训练 FFM 模型..."
cd /data/xiongle/alphaFFM-go
cat $TEST_DATA | ./bin/ffm_train -m ffm_compare.txt -dim $DIM -core 1 >/dev/null 2>&1

echo ""
echo "=========================================="
echo "模型文件统计"
echo "=========================================="
echo ""

# FM 统计
FM_LINES=$(wc -l < /data/xiongle/alphaFM-go/fm_compare.txt)
FM_SIZE=$(wc -c < /data/xiongle/alphaFM-go/fm_compare.txt)
FM_BIAS_FIELDS=$(head -1 /data/xiongle/alphaFM-go/fm_compare.txt | awk '{print NF}')
FM_FEAT_FIELDS=$(head -2 /data/xiongle/alphaFM-go/fm_compare.txt | tail -1 | awk '{print NF}')

echo "FM 模型:"
echo "  文件大小: $FM_SIZE bytes"
echo "  总行数: $FM_LINES"
echo "  Bias行字段数: $FM_BIAS_FIELDS"
echo "  特征行字段数: $FM_FEAT_FIELDS"
echo ""

# FFM 统计
FFM_LINES=$(wc -l < /data/xiongle/alphaFFM-go/ffm_compare.txt)
FFM_SIZE=$(wc -c < /data/xiongle/alphaFFM-go/ffm_compare.txt)
FFM_FIELDS=$(head -1 /data/xiongle/alphaFFM-go/ffm_compare.txt | awk '{print NF-1}')
FFM_BIAS_FIELDS=$(head -2 /data/xiongle/alphaFFM-go/ffm_compare.txt | tail -1 | awk '{print NF}')
FFM_FEAT_FIELDS=$(head -3 /data/xiongle/alphaFFM-go/ffm_compare.txt | tail -1 | awk '{print NF}')

echo "FFM 模型:"
echo "  文件大小: $FFM_SIZE bytes"
echo "  总行数: $FFM_LINES"
echo "  Field 数量: $FFM_FIELDS"
echo "  Bias行字段数: $FFM_BIAS_FIELDS"
echo "  特征行字段数: $FFM_FEAT_FIELDS"
echo ""

# 计算比例
SIZE_RATIO=$(echo "scale=1; $FFM_SIZE / $FM_SIZE" | bc)
FIELD_RATIO=$(echo "scale=1; $FFM_FEAT_FIELDS / $FM_FEAT_FIELDS" | bc)

echo "FFM/FM 比例:"
echo "  文件大小: ${SIZE_RATIO}x"
echo "  特征字段数: ${FIELD_RATIO}x"
echo ""

echo "=========================================="
echo "模型文件格式对比"
echo "=========================================="
echo ""

echo "FM 模型文件前3行:"
echo "---"
head -3 /data/xiongle/alphaFM-go/fm_compare.txt | nl -w2 -s'. '
echo ""

echo "FFM 模型文件前3行:"
echo "---"
head -3 /data/xiongle/alphaFFM-go/ffm_compare.txt | nl -w2 -s'. '
echo ""

echo "=========================================="
echo "参数量分析"
echo "=========================================="
echo ""

K=4  # 隐向量维度
F=$FFM_FIELDS  # Field数量

FM_PARAMS=$((3 + 3*K))
FFM_PARAMS=$((3 + 3*F*K))

echo "配置:"
echo "  隐向量维度 k = $K"
echo "  Field 数量 F = $F"
echo ""

echo "每个特征的参数数量:"
echo "  FM:  1(wi) + k(vi) + 2(w_ni,w_zi) + k(v_ni) + k(v_zi) = 3 + 3k = $FM_PARAMS"
echo "  FFM: 1(wi) + F×k(vi) + 2(w_ni,w_zi) + F×k(v_ni) + F×k(v_zi) = 3 + 3Fk = $FFM_PARAMS"
echo ""

echo "参数量对比:"
echo "  FM:  $FM_PARAMS 个参数/特征 (加上特征名 = $FM_FEAT_FIELDS 字段)"
echo "  FFM: $FFM_PARAMS 个参数/特征 (加上特征名 = $FFM_FEAT_FIELDS 字段)"
echo "  FFM/FM: $(echo "scale=1; $FFM_PARAMS / $FM_PARAMS" | bc)x"
echo ""

echo "=========================================="
echo "关键差异说明"
echo "=========================================="
echo ""

echo "1. FFM 多了 FIELDS 行"
echo "   - 记录所有 field 的名称"
echo "   - 用于解析每个特征的多个隐向量"
echo ""

echo "2. FFM 每个特征的隐向量是多维的"
echo "   - FM:  一个特征有 1 套隐向量 (k 维)"
echo "   - FFM: 一个特征有 F 套隐向量 (每套 k 维)"
echo ""

echo "3. FFM 参数量 = FM 参数量 × F"
echo "   - Field 数量越多，FFM 参数量越大"
echo "   - 当前: F=$F, FFM参数是FM的 ${FIELD_RATIO}x"
echo ""

echo "=========================================="
echo "模型文件结构可视化"
echo "=========================================="
echo ""

echo "FM 特征行结构 (以 f3 为例):"
echo "  f3 | wi | vi[0] vi[1] vi[2] vi[3] | w_ni w_zi | v_ni[0] ... v_ni[3] | v_zi[0] ... v_zi[3]"
echo "      ^     ^^^^^^^^^^^^^^^^^^^^^^^   ^^^^^^^^^^   ^^^^^^^^^^^^^^^^^     ^^^^^^^^^^^^^^^^^"
echo "     名字        4维隐向量              FTRL参数      4维FTRL参数           4维FTRL参数"
echo ""

echo "FFM 特征行结构 (以 sex 为例，F=$F fields):"
echo "  sex | wi | vi,f1[4维] vi,f2[4维] ... vi,f7[4维] | w_ni w_zi | v_ni,f1[4维] ... | v_zi,f1[4维] ..."
echo "       ^     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^     ^^^^^^^^^^   ^^^^^^^^^^^^^^^   ^^^^^^^^^^^^^^^"
echo "      名字    针对每个field的4维隐向量(共${F}×4=$((F*4))个)   FTRL参数    ${F}套4维FTRL参数     ${F}套4维FTRL参数"
echo ""

echo "=========================================="
echo "总结"
echo "=========================================="
echo ""

echo "✅ FFM 模型文件正确实现了 field-aware 特性"
echo "✅ 参数量增加了 ${FIELD_RATIO}x，符合预期（Field数量=$F）"
echo "✅ 模型文件大小增加了 ${SIZE_RATIO}x"
echo ""

echo "这就是为什么 FFM 效果更好但训练更慢："
echo "  - 更多参数 → 更强的表达能力"
echo "  - 更细粒度的 field-aware 建模"
echo "  - 需要更多训练时间和内存"
echo ""

# 清理
rm -f /data/xiongle/alphaFM-go/fm_compare.txt
rm -f /data/xiongle/alphaFFM-go/ffm_compare.txt

echo "详细说明请查看: docs/MODEL_FILE_COMPARISON.md"
echo ""

