#!/bin/bash

# Weaver DI 라이브러리 완벽한 테스트 실행 스크립트

set -e  # 에러 발생 시 스크립트 중단

echo "🧪 Weaver DI 라이브러리 완벽한 테스트 시작"
echo "=================================================="

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 함수 정의
print_header() {
    echo -e "\n${BLUE}$1${NC}"
    echo "----------------------------------------"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 시스템 정보 출력
print_header "시스템 정보"
echo "OS: $(uname -s)"
echo "Architecture: $(uname -m)"
echo "Swift Version: $(swift --version | head -n1)"
echo "Xcode Version: $(xcodebuild -version | head -n1 2>/dev/null || echo 'Xcode not found')"

# 패키지 정보 확인
print_header "패키지 정보 확인"
if [ -f "Package.swift" ]; then
    print_success "Package.swift 발견"
    echo "Swift Tools Version: $(head -n1 Package.swift | grep -o '[0-9]\+\.[0-9]\+')"
else
    print_error "Package.swift를 찾을 수 없습니다"
    exit 1
fi

# 의존성 해결
print_header "의존성 해결"
echo "swift package resolve 실행 중..."
if swift package resolve; then
    print_success "의존성 해결 완료"
else
    print_error "의존성 해결 실패"
    exit 1
fi

# 빌드 테스트
print_header "빌드 테스트"
echo "swift build 실행 중..."
if swift build; then
    print_success "빌드 성공"
else
    print_error "빌드 실패"
    exit 1
fi

# 릴리즈 빌드 테스트
print_header "릴리즈 빌드 테스트"
echo "swift build -c release 실행 중..."
if swift build -c release; then
    print_success "릴리즈 빌드 성공"
else
    print_warning "릴리즈 빌드 실패 (계속 진행)"
fi

# 테스트 실행 함수
run_test_suite() {
    local suite_name=$1
    local filter=$2
    
    print_header "$suite_name 테스트"
    echo "swift test --filter \"$filter\" 실행 중..."
    
    if swift test --filter "$filter" --parallel; then
        print_success "$suite_name 테스트 통과"
        return 0
    else
        print_error "$suite_name 테스트 실패"
        return 1
    fi
}

# 개별 테스트 스위트 실행
test_results=()

# Foundation Layer 테스트
if run_test_suite "Foundation Layer" "FoundationLayerTests"; then
    test_results+=("Foundation: ✅")
else
    test_results+=("Foundation: ❌")
fi

# Core Layer 테스트
if run_test_suite "Core Layer" "CoreLayerIntegrationTests"; then
    test_results+=("Core: ✅")
else
    test_results+=("Core: ❌")
fi

# Orchestration Layer 테스트
if run_test_suite "Orchestration Layer" "OrchestrationLayerTests"; then
    test_results+=("Orchestration: ✅")
else
    test_results+=("Orchestration: ❌")
fi

# Application Layer 테스트
if run_test_suite "Application Layer" "ApplicationLayerTests"; then
    test_results+=("Application: ✅")
else
    test_results+=("Application: ❌")
fi

# System Integration 테스트
if run_test_suite "System Integration" "SystemIntegrationTests"; then
    test_results+=("Integration: ✅")
else
    test_results+=("Integration: ❌")
fi

# 기존 테스트들도 실행
print_header "기존 테스트 스위트 실행"

existing_tests=(
    "RegistrationAndResolutionTests"
    "ConcurrencyTests"
    "ScopeLifecycleTests"
    "WeaverKernelTests"
    "InjectPropertyWrapperTests"
    "ContainerEdgeCaseTests"
    "AdvancedFeaturesTests"
)

for test in "${existing_tests[@]}"; do
    if run_test_suite "$test" "$test"; then
        test_results+=("$test: ✅")
    else
        test_results+=("$test: ❌")
    fi
done

# 전체 테스트 실행 (최종 검증)
print_header "전체 테스트 실행"
echo "swift test --parallel 실행 중..."

start_time=$(date +%s)
if swift test --parallel; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    print_success "전체 테스트 통과 (소요 시간: ${duration}초)"
    overall_result="✅ 성공"
else
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    print_error "전체 테스트 실패 (소요 시간: ${duration}초)"
    overall_result="❌ 실패"
fi

# 성능 벤치마크 (선택적)
if [ "$1" = "--benchmark" ]; then
    print_header "성능 벤치마크"
    echo "성능 벤치마크 테스트 실행 중..."
    if swift test --filter "benchmark" --parallel; then
        print_success "성능 벤치마크 완료"
    else
        print_warning "성능 벤치마크 실패"
    fi
fi

# 메모리 테스트 (선택적)
if [ "$1" = "--memory" ]; then
    print_header "메모리 테스트"
    echo "메모리 관련 테스트 실행 중..."
    if swift test --filter "memory" --parallel; then
        print_success "메모리 테스트 완료"
    else
        print_warning "메모리 테스트 실패"
    fi
fi

# 결과 요약
print_header "테스트 결과 요약"
echo "전체 결과: $overall_result"
echo ""
echo "개별 테스트 결과:"
for result in "${test_results[@]}"; do
    echo "  $result"
done

# 추가 정보
print_header "추가 정보"
echo "📊 테스트 커버리지 확인: swift test --enable-code-coverage"
echo "🔍 상세 로그 확인: swift test --verbose"
echo "🚀 성능 벤치마크: ./test-runner.sh --benchmark"
echo "💾 메모리 테스트: ./test-runner.sh --memory"
echo ""
echo "📖 테스트 계획 문서: Tests/WeaverTests/ComprehensiveTestPlan.md"

# 최종 상태 코드 반환
if [[ "$overall_result" == *"성공"* ]]; then
    echo ""
    print_success "🎉 모든 테스트가 성공적으로 완료되었습니다!"
    exit 0
else
    echo ""
    print_error "💥 일부 테스트가 실패했습니다. 로그를 확인해주세요."
    exit 1
fi