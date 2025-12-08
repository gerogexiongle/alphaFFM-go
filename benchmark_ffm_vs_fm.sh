#!/bin/bash

# alphaFFM vs alphaFM 性能对比测试脚本
# FFM vs FM 性能基准测试

set -e

echo "=========================================================="
echo "  alphaFFM vs alphaFM Performance Benchmark"
echo "=========================================================="
echo

# ===== 配置参数 =====
FFM_DIR="/data/xiongle/alphaFFM-go"
FM_DIR="/data/xiongle/alphaFM-go"
TRAIN_DATA_DIR="/data/xiongle/data/train/feature"
TEST_DATA_DIR="/data/xiongle/data/test/feature"

# 输出目录
BENCHMARK_DIR="$FFM_DIR/benchmark_results"
mkdir -p "$BENCHMARK_DIR"

# 模型文件（使用文本格式）
FFM_MODEL="$BENCHMARK_DIR/ffm_model.txt"
FM_MODEL="$BENCHMARK_DIR/fm_model.txt"

# 预测结果文件
FFM_PREDICTION="$BENCHMARK_DIR/ffm_prediction.txt"
FM_PREDICTION="$BENCHMARK_DIR/fm_prediction.txt"

# ===== 可调参数（方便快速修改） =====
# 隐向量维度 (二阶交互的向量维度)
FACTOR_DIM=64

# SIMD 模式: "blas" (使用 BLAS 库加速) 或 "scalar" (纯标量计算)
# FFM 和 FM 都支持 SIMD 优化
SIMD_MODE="blas"

# 并行线程数
THREAD_NUM=4

# 性能日志文件
PERF_LOG="$BENCHMARK_DIR/performance_report_dim${FACTOR_DIM}_${SIMD_MODE}.txt"

# FFM 训练/预测参数（带 SIMD 支持）
FFM_TRAIN_PARAMS="-dim 1,1,${FACTOR_DIM} -core ${THREAD_NUM} -w_alpha 0.05 -w_beta 1.0 -w_l1 0.1 -w_l2 5.0 -v_alpha 0.05 -v_beta 1.0 -v_l1 0.1 -v_l2 5.0 -init_stdev 0.001 -mf txt -simd ${SIMD_MODE}"
FFM_PREDICT_PARAMS="-dim ${FACTOR_DIM} -mf txt -core ${THREAD_NUM} -simd ${SIMD_MODE}"

# FM 训练/预测参数（带 SIMD 支持）
FM_TRAIN_PARAMS="-dim 1,1,${FACTOR_DIM} -core ${THREAD_NUM} -w_alpha 0.05 -w_beta 1.0 -w_l1 0.1 -w_l2 5.0 -v_alpha 0.05 -v_beta 1.0 -v_l1 0.1 -v_l2 5.0 -init_stdev 0.001 -mf txt -simd ${SIMD_MODE}"
FM_PREDICT_PARAMS="-dim ${FACTOR_DIM} -mf txt -simd ${SIMD_MODE}"

echo "Configuration:"
echo "  FFM Directory: $FFM_DIR"
echo "  FM Directory:  $FM_DIR"
echo "  Train Data:    $TRAIN_DATA_DIR"
echo "  Test Data:     $TEST_DATA_DIR"
echo "  Results Dir:   $BENCHMARK_DIR"
echo "  Factor Dim:    $FACTOR_DIM"
echo "  SIMD Mode:     $SIMD_MODE (both FFM and FM)"
echo "  Threads:       $THREAD_NUM"
echo

# ===== 函数定义 =====

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "Error: $1 is not installed"
        exit 1
    fi
}

# 获取进程峰值内存 (KB)
get_peak_memory() {
    local pid=$1
    local max_mem=0
    while kill -0 $pid 2>/dev/null; do
        if [ -f /proc/$pid/status ]; then
            local mem=$(grep VmRSS /proc/$pid/status | awk '{print $2}')
            if [ -n "$mem" ] && [ $mem -gt $max_mem ]; then
                max_mem=$mem
            fi
        fi
        sleep 0.1
    done
    echo $max_mem
}

# 合并多个part文件并计算统计信息
merge_and_stats() {
    local data_dir=$1
    local desc=$2
    echo "  $desc:"
    local file_count=$(ls -1 $data_dir/part-*.txt 2>/dev/null | wc -l)
    local total_size=$(du -sh $data_dir 2>/dev/null | awk '{print $1}')
    local total_lines=$(cat $data_dir/part-*.txt 2>/dev/null | wc -l)
    echo "    Files: $file_count"
    echo "    Total Size: $total_size"
    echo "    Total Lines: $total_lines"
    echo
}

# 格式化内存显示
format_memory() {
    local mem_kb=$1
    if [ $mem_kb -lt 1024 ]; then
        echo "${mem_kb} KB"
    elif [ $mem_kb -lt 1048576 ]; then
        echo "$(echo "scale=2; $mem_kb/1024" | bc) MB"
    else
        echo "$(echo "scale=2; $mem_kb/1048576" | bc) GB"
    fi
}

# ===== 步骤 1: 环境检查 =====
echo "Step 1: Environment Check"
echo "----------------------------------------"

check_command bc
check_command time

# 检查 FFM 编译状态
if [ ! -f "$FFM_DIR/bin/ffm_train" ] || [ ! -f "$FFM_DIR/bin/ffm_predict" ]; then
    echo "  Compiling FFM version..."
    cd $FFM_DIR && make clean && make
    echo "  ✓ FFM version compiled"
else
    echo "  ✓ FFM version ready"
fi

# 检查 FM 编译状态
if [ ! -f "$FM_DIR/bin/fm_train" ] || [ ! -f "$FM_DIR/bin/fm_predict" ]; then
    echo "  Compiling FM version..."
    cd $FM_DIR && make clean && make
    echo "  ✓ FM version compiled"
else
    echo "  ✓ FM version ready"
fi

echo

# ===== 步骤 2: 数据集信息 =====
echo "Step 2: Dataset Information"
echo "----------------------------------------"
merge_and_stats "$TRAIN_DATA_DIR" "Training Data"
merge_and_stats "$TEST_DATA_DIR" "Test Data"

# 清空性能日志
echo "=========================================================="  > $PERF_LOG
echo "  alphaFFM vs alphaFM Performance Benchmark Report"        >> $PERF_LOG
echo "  Generated: $(date)"                                       >> $PERF_LOG
echo "=========================================================="  >> $PERF_LOG
echo                                                                >> $PERF_LOG
echo "Configuration:"                                              >> $PERF_LOG
echo "  Factor Dimension: $FACTOR_DIM"                            >> $PERF_LOG
echo "  Thread Count: $THREAD_NUM"                                >> $PERF_LOG
echo "  SIMD Mode: $SIMD_MODE (both FFM and FM)"                  >> $PERF_LOG
echo                                                                >> $PERF_LOG

# ===== 步骤 3: FFM 版本训练 =====
echo "Step 3: Training with FFM Version"
echo "----------------------------------------"

echo "  Streaming training data file by file (to reduce memory pressure)..."
echo "  (Preprocessing: converting format from 'userID itemID label features...' to 'label features...')"
cd $FFM_DIR

FFM_TRAIN_START=$(date +%s)
(find $TRAIN_DATA_DIR -type f -name "part-*.txt" | sort | while read file; do
    cat "$file" | awk '{printf "%s", $3; for(i=4; i<=NF; i++) printf " %s", $i; printf "\n"}'
done | /usr/bin/time -v ./bin/ffm_train $FFM_TRAIN_PARAMS -m $FFM_MODEL) 2>&1 | tee $BENCHMARK_DIR/ffm_train.log &
FFM_TRAIN_PID=$!

# 监控内存使用
FFM_TRAIN_MEM=$(get_peak_memory $FFM_TRAIN_PID)
wait $FFM_TRAIN_PID
FFM_TRAIN_EXIT=$?
FFM_TRAIN_END=$(date +%s)
FFM_TRAIN_TIME=$((FFM_TRAIN_END - FFM_TRAIN_START))

if [ $FFM_TRAIN_EXIT -eq 0 ]; then
    echo "  ✓ FFM training completed"
    echo "    Time: ${FFM_TRAIN_TIME}s"
    echo "    Peak Memory: $(format_memory $FFM_TRAIN_MEM)"
else
    echo "  ✗ FFM training failed"
    exit 1
fi

# 提取训练日志中的关键信息
FFM_ITERATIONS=$(grep -oP 'iter:\s*\K\d+' $BENCHMARK_DIR/ffm_train.log | tail -1)
FFM_FINAL_LOSS=$(grep -oP 'tr-loss:\s*\K[0-9.]+' $BENCHMARK_DIR/ffm_train.log | tail -1)

echo >> $PERF_LOG
echo "FFM Training Performance:" >> $PERF_LOG
echo "  Training Time: ${FFM_TRAIN_TIME}s" >> $PERF_LOG
echo "  Peak Memory: $(format_memory $FFM_TRAIN_MEM)" >> $PERF_LOG
echo "  Iterations: $FFM_ITERATIONS" >> $PERF_LOG
echo "  Final Loss: $FFM_FINAL_LOSS" >> $PERF_LOG

echo

# ===== 步骤 4: FM 版本训练 =====
echo "Step 4: Training with FM Version"
echo "----------------------------------------"

echo "  Streaming training data file by file (to reduce memory pressure)..."
echo "  (Preprocessing: converting format from 'userID itemID label features...' to 'label features...')"
cd $FM_DIR

FM_TRAIN_START=$(date +%s)
(find $TRAIN_DATA_DIR -type f -name "part-*.txt" | sort | while read file; do
    cat "$file" | awk '{printf "%s", $3; for(i=4; i<=NF; i++) printf " %s", $i; printf "\n"}'
done | /usr/bin/time -v ./bin/fm_train $FM_TRAIN_PARAMS -m $FM_MODEL) 2>&1 | tee $BENCHMARK_DIR/fm_train.log &
FM_TRAIN_PID=$!

# 监控内存使用
FM_TRAIN_MEM=$(get_peak_memory $FM_TRAIN_PID)
wait $FM_TRAIN_PID
FM_TRAIN_EXIT=$?
FM_TRAIN_END=$(date +%s)
FM_TRAIN_TIME=$((FM_TRAIN_END - FM_TRAIN_START))

if [ $FM_TRAIN_EXIT -eq 0 ]; then
    echo "  ✓ FM training completed"
    echo "    Time: ${FM_TRAIN_TIME}s"
    echo "    Peak Memory: $(format_memory $FM_TRAIN_MEM)"
else
    echo "  ✗ FM training failed"
    exit 1
fi

# 提取训练日志中的关键信息
FM_ITERATIONS=$(grep -oP 'iter:\s*\K\d+' $BENCHMARK_DIR/fm_train.log | tail -1)
FM_FINAL_LOSS=$(grep -oP 'tr-loss:\s*\K[0-9.]+' $BENCHMARK_DIR/fm_train.log | tail -1)

echo >> $PERF_LOG
echo "FM Training Performance:" >> $PERF_LOG
echo "  Training Time: ${FM_TRAIN_TIME}s" >> $PERF_LOG
echo "  Peak Memory: $(format_memory $FM_TRAIN_MEM)" >> $PERF_LOG
echo "  Iterations: $FM_ITERATIONS" >> $PERF_LOG
echo "  Final Loss: $FM_FINAL_LOSS" >> $PERF_LOG

echo

# ===== 步骤 5: 训练性能对比 =====
echo "Step 5: Training Performance Comparison"
echo "----------------------------------------"

# 计算性能比率 (FFM 相对于 FM)
TRAIN_TIME_RATIO=$(echo "scale=2; $FFM_TRAIN_TIME/$FM_TRAIN_TIME" | bc)
TRAIN_MEM_RATIO=$(echo "scale=2; $FFM_TRAIN_MEM/$FM_TRAIN_MEM" | bc)

echo "  Training Time:"
echo "    FFM: ${FFM_TRAIN_TIME}s"
echo "    FM:  ${FM_TRAIN_TIME}s"
echo "    Ratio (FFM/FM): ${TRAIN_TIME_RATIO}x"
echo
echo "  Peak Memory:"
echo "    FFM: $(format_memory $FFM_TRAIN_MEM)"
echo "    FM:  $(format_memory $FM_TRAIN_MEM)"
echo "    Ratio (FFM/FM): ${TRAIN_MEM_RATIO}x"
echo
echo "  Model Quality:"
echo "    FFM Final Loss: $FFM_FINAL_LOSS (${FFM_ITERATIONS} iters)"
echo "    FM Final Loss:  $FM_FINAL_LOSS (${FM_ITERATIONS} iters)"
echo

echo >> $PERF_LOG
echo "Training Performance Comparison:" >> $PERF_LOG
echo "  Time Ratio (FFM/FM): ${TRAIN_TIME_RATIO}x" >> $PERF_LOG
echo "  Memory Ratio (FFM/FM): ${TRAIN_MEM_RATIO}x" >> $PERF_LOG
echo >> $PERF_LOG

# ===== 步骤 6: FFM 版本预测 =====
echo "Step 6: Prediction with FFM Version"
echo "----------------------------------------"

echo "  Streaming test data file by file (to reduce memory pressure)..."
echo "  (Preprocessing: converting format from 'userID itemID label features...' to 'label features...')"
cd $FFM_DIR

FFM_PRED_START=$(date +%s)
(find $TEST_DATA_DIR -type f -name "part-*.txt" | sort | while read file; do
    cat "$file" | awk '{printf "%s", $3; for(i=4; i<=NF; i++) printf " %s", $i; printf "\n"}'
done | /usr/bin/time -v ./bin/ffm_predict $FFM_PREDICT_PARAMS -m $FFM_MODEL -out $FFM_PREDICTION) 2>&1 | tee $BENCHMARK_DIR/ffm_predict.log &
FFM_PRED_PID=$!

# 监控内存使用
FFM_PRED_MEM=$(get_peak_memory $FFM_PRED_PID)
wait $FFM_PRED_PID
FFM_PRED_EXIT=$?
FFM_PRED_END=$(date +%s)
FFM_PRED_TIME=$((FFM_PRED_END - FFM_PRED_START))

if [ $FFM_PRED_EXIT -eq 0 ]; then
    echo "  ✓ FFM prediction completed"
    echo "    Time: ${FFM_PRED_TIME}s"
    echo "    Peak Memory: $(format_memory $FFM_PRED_MEM)"
else
    echo "  ✗ FFM prediction failed"
    exit 1
fi

FFM_PRED_COUNT=$(wc -l < $FFM_PREDICTION)
echo "    Predictions: $FFM_PRED_COUNT"

echo >> $PERF_LOG
echo "FFM Prediction Performance:" >> $PERF_LOG
echo "  Prediction Time: ${FFM_PRED_TIME}s" >> $PERF_LOG
echo "  Peak Memory: $(format_memory $FFM_PRED_MEM)" >> $PERF_LOG
echo "  Predictions: $FFM_PRED_COUNT" >> $PERF_LOG

echo

# ===== 步骤 7: FM 版本预测 =====
echo "Step 7: Prediction with FM Version"
echo "----------------------------------------"

echo "  Streaming test data file by file (to reduce memory pressure)..."
echo "  (Preprocessing: converting format from 'userID itemID label features...' to 'label features...')"
cd $FM_DIR

FM_PRED_START=$(date +%s)
(find $TEST_DATA_DIR -type f -name "part-*.txt" | sort | while read file; do
    cat "$file" | awk '{printf "%s", $3; for(i=4; i<=NF; i++) printf " %s", $i; printf "\n"}'
done | /usr/bin/time -v ./bin/fm_predict $FM_PREDICT_PARAMS -m $FM_MODEL -out $FM_PREDICTION) 2>&1 | tee $BENCHMARK_DIR/fm_predict.log &
FM_PRED_PID=$!

# 监控内存使用
FM_PRED_MEM=$(get_peak_memory $FM_PRED_PID)
wait $FM_PRED_PID
FM_PRED_EXIT=$?
FM_PRED_END=$(date +%s)
FM_PRED_TIME=$((FM_PRED_END - FM_PRED_START))

if [ $FM_PRED_EXIT -eq 0 ]; then
    echo "  ✓ FM prediction completed"
    echo "    Time: ${FM_PRED_TIME}s"
    echo "    Peak Memory: $(format_memory $FM_PRED_MEM)"
else
    echo "  ✗ FM prediction failed"
    exit 1
fi

FM_PRED_COUNT=$(wc -l < $FM_PREDICTION)
echo "    Predictions: $FM_PRED_COUNT"

echo >> $PERF_LOG
echo "FM Prediction Performance:" >> $PERF_LOG
echo "  Prediction Time: ${FM_PRED_TIME}s" >> $PERF_LOG
echo "  Peak Memory: $(format_memory $FM_PRED_MEM)" >> $PERF_LOG
echo "  Predictions: $FM_PRED_COUNT" >> $PERF_LOG

echo

# ===== 步骤 8: 预测性能对比 =====
echo "Step 8: Prediction Performance Comparison"
echo "----------------------------------------"

# 计算性能比率 (FFM 相对于 FM)
PRED_TIME_RATIO=$(echo "scale=2; $FFM_PRED_TIME/$FM_PRED_TIME" | bc)
PRED_MEM_RATIO=$(echo "scale=2; $FFM_PRED_MEM/$FM_PRED_MEM" | bc)

echo "  Prediction Time:"
echo "    FFM: ${FFM_PRED_TIME}s"
echo "    FM:  ${FM_PRED_TIME}s"
echo "    Ratio (FFM/FM): ${PRED_TIME_RATIO}x"
echo
echo "  Peak Memory:"
echo "    FFM: $(format_memory $FFM_PRED_MEM)"
echo "    FM:  $(format_memory $FM_PRED_MEM)"
echo "    Ratio (FFM/FM): ${PRED_MEM_RATIO}x"
echo

echo >> $PERF_LOG
echo "Prediction Performance Comparison:" >> $PERF_LOG
echo "  Time Ratio (FFM/FM): ${PRED_TIME_RATIO}x" >> $PERF_LOG
echo "  Memory Ratio (FFM/FM): ${PRED_MEM_RATIO}x" >> $PERF_LOG
echo >> $PERF_LOG

# ===== 步骤 9: 预测结果对比 =====
echo "Step 9: Prediction Results Comparison"
echo "----------------------------------------"

echo "  Comparing first 10 predictions:"
echo
echo "  FFM predictions:"
head -10 $FFM_PREDICTION | nl
echo
echo "  FM predictions:"
head -10 $FM_PREDICTION | nl
echo

# 计算预测值的统计差异
echo "  Computing statistical differences..."

# 使用 awk 计算差异
awk 'NR==FNR{ffm[NR]=$0; next} {diff=$0-ffm[FNR]; sum+=diff; sumsq+=diff*diff; abssum+=(diff<0?-diff:diff); count++} END {
    if(count>0) {
        mean=sum/count;
        variance=sumsq/count-mean*mean;
        stddev=sqrt(variance);
        mae=abssum/count;
        printf "    Mean Difference: %.6f\n", mean;
        printf "    Std Deviation: %.6f\n", stddev;
        printf "    Mean Absolute Error: %.6f\n", mae;
        printf "    Total Comparisons: %d\n", count;
    }
}' $FFM_PREDICTION $FM_PREDICTION | tee -a $PERF_LOG

echo

# ===== 步骤 10: AUC 评估对比 =====
echo "Step 10: AUC Evaluation"
echo "----------------------------------------"

# 初始化 AUC 相关变量
FFM_AUC="N/A"
FM_AUC="N/A"
AUC_DIFF="N/A"
AUC_IMPROVE="N/A"

# 检查 Python 和 sklearn 是否可用
if ! command -v python &> /dev/null; then
    echo "  ⚠ Warning: Python not found, skipping AUC calculation"
else
    # 检查 get_auc.py 是否存在
    if [ ! -f "$FFM_DIR/get_auc.py" ]; then
        echo "  ⚠ Warning: get_auc.py not found, skipping AUC calculation"
    else
        echo "  Calculating AUC scores..."
        
        # 计算 FFM AUC
        echo -n "    FFM AUC: "
        FFM_AUC=$(python $FFM_DIR/get_auc.py $FFM_PREDICTION 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "$FFM_AUC"
        else
            echo "Failed"
            FFM_AUC="N/A"
        fi
        
        # 计算 FM AUC
        echo -n "    FM AUC:  "
        FM_AUC=$(python $FFM_DIR/get_auc.py $FM_PREDICTION 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "$FM_AUC"
        else
            echo "Failed"
            FM_AUC="N/A"
        fi
        
        # 计算 AUC 差异
        if [ "$FFM_AUC" != "N/A" ] && [ "$FM_AUC" != "N/A" ]; then
            AUC_DIFF=$(echo "scale=6; $FFM_AUC - $FM_AUC" | bc)
            AUC_IMPROVE=$(echo "scale=4; ($FFM_AUC - $FM_AUC) * 100 / $FM_AUC" | bc)
            echo "    AUC Difference (FFM - FM): $AUC_DIFF"
            echo "    Relative Improvement: ${AUC_IMPROVE}%"
            
            # 写入报告
            echo >> $PERF_LOG
            echo "AUC Evaluation:" >> $PERF_LOG
            echo "  FFM AUC: $FFM_AUC" >> $PERF_LOG
            echo "  FM AUC:  $FM_AUC" >> $PERF_LOG
            echo "  AUC Difference (FFM - FM): $AUC_DIFF" >> $PERF_LOG
            echo "  Relative Improvement: ${AUC_IMPROVE}%" >> $PERF_LOG
            
            # 判断哪个模型更好
            if (( $(echo "$FFM_AUC > $FM_AUC" | bc -l) )); then
                echo "    ✓ FFM achieves better AUC"
                echo "  Winner: FFM (better AUC)" >> $PERF_LOG
            elif (( $(echo "$FM_AUC > $FFM_AUC" | bc -l) )); then
                echo "    ✓ FM achieves better AUC"
                echo "  Winner: FM (better AUC)" >> $PERF_LOG
            else
                echo "    = Both models achieve the same AUC"
                echo "  Winner: Tie" >> $PERF_LOG
            fi
        else
            echo "    ⚠ AUC comparison skipped due to calculation errors"
        fi
    fi
fi

echo

# ===== 步骤 11: 模型复杂度分析 =====
echo "Step 11: Model Complexity Analysis"
echo "----------------------------------------"

FFM_MODEL_SIZE=$(ls -lh $FFM_MODEL | awk '{print $5}')
FM_MODEL_SIZE=$(ls -lh $FM_MODEL | awk '{print $5}')

FFM_MODEL_LINES=$(wc -l < $FFM_MODEL)
FM_MODEL_LINES=$(wc -l < $FM_MODEL)

echo "  Model File Size:"
echo "    FFM: $FFM_MODEL_SIZE ($FFM_MODEL_LINES lines)"
echo "    FM:  $FM_MODEL_SIZE ($FM_MODEL_LINES lines)"
echo

# 分析模型结构
echo "  FFM Model Structure:"
head -5 $FFM_MODEL | sed 's/^/    /'
echo

echo "  FM Model Structure:"
head -5 $FM_MODEL | sed 's/^/    /'
echo

echo >> $PERF_LOG
echo "Model Complexity:" >> $PERF_LOG
echo "  FFM Model: $FFM_MODEL_SIZE ($FFM_MODEL_LINES lines)" >> $PERF_LOG
echo "  FM Model:  $FM_MODEL_SIZE ($FM_MODEL_LINES lines)" >> $PERF_LOG
echo >> $PERF_LOG

# ===== 步骤 12: 生成最终报告 =====
echo "Step 12: Final Report"
echo "----------------------------------------"

# 构建 AUC 报告部分
AUC_REPORT=""
if [ -n "$FFM_AUC" ] && [ "$FFM_AUC" != "N/A" ]; then
    AUC_REPORT="
Model Quality (AUC):
  FFM: $FFM_AUC
  FM:  $FM_AUC
  Difference: $AUC_DIFF (${AUC_IMPROVE}% improvement)"
else
    AUC_REPORT="
Model Quality (AUC):
  Not available (Python/sklearn not found or calculation failed)"
fi

cat >> $PERF_LOG << EOF

========================================================
Overall Summary
========================================================

Algorithm Comparison: FFM (Field-aware FM) vs FM (Factorization Machine)

Training:
  FFM: ${FFM_TRAIN_TIME}s, $(format_memory $FFM_TRAIN_MEM), Loss: $FFM_FINAL_LOSS
  FM:  ${FM_TRAIN_TIME}s, $(format_memory $FM_TRAIN_MEM), Loss: $FM_FINAL_LOSS
  Performance: FFM is ${TRAIN_TIME_RATIO}x in time, ${TRAIN_MEM_RATIO}x in memory

Prediction:
  FFM: ${FFM_PRED_TIME}s, $(format_memory $FFM_PRED_MEM)
  FM:  ${FM_PRED_TIME}s, $(format_memory $FM_PRED_MEM)
  Performance: FFM is ${PRED_TIME_RATIO}x in time, ${PRED_MEM_RATIO}x in memory
$AUC_REPORT

Model Complexity:
  FFM: $FFM_MODEL_SIZE ($FFM_MODEL_LINES lines)
  FM:  $FM_MODEL_SIZE ($FM_MODEL_LINES lines)

Result Files:
  FFM Predictions: $FFM_PRED_COUNT lines
  FM Predictions:  $FM_PRED_COUNT lines

Key Insights:
  - FFM considers field information, leading to more complex interactions
  - FM uses global latent factors, potentially more efficient but less expressive
  - Trade-off between model expressiveness (FFM) and computational efficiency (FM)
  - FFM typically achieves better AUC but requires more computation time and memory

========================================================
EOF

echo "  ✓ Performance report saved to: $PERF_LOG"
echo

# 显示报告摘要
cat $PERF_LOG

# ===== 清理选项 =====
echo
echo "=========================================================="
echo "Benchmark completed!"
echo "=========================================================="
echo
echo "Results saved in: $BENCHMARK_DIR"
echo "  - Performance report: performance_report_dim${FACTOR_DIM}.txt"
echo "  - Training logs: ffm_train.log, fm_train.log"
echo "  - Prediction logs: ffm_predict.log, fm_predict.log"
echo "  - Models: ffm_model.txt, fm_model.txt"
echo "  - Predictions: ffm_prediction.txt, fm_prediction.txt"
echo

read -p "Delete benchmark files? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleaning up..."
    rm -f $FFM_MODEL $FM_MODEL
    rm -f $FFM_PREDICTION $FM_PREDICTION
    rm -f $BENCHMARK_DIR/*.log
    echo "✓ Cleaned up (performance report kept)"
fi

echo
echo "Done!"

