# 🎯 **Weaver 스코프 설계 가이드라인**

## **목차**
1. [스코프 개요](#스코프-개요)
2. [스코프별 상세 가이드](#스코프별-상세-가이드)
3. [스코프 선택 결정 트리](#스코프-선택-결정-트리)
4. [실전 예시](#실전-예시)
5. [성능 최적화 팁](#성능-최적화-팁)
6. [안티패턴과 해결책](#안티패턴과-해결책)

---

## **스코프 개요**

Weaver의 스코프 시스템은 의존성의 생명주기와 초기화 시점을 제어하여 앱 성능과 메모리 효율성을 최적화합니다.

### **스코프 생명주기 순서**
```
.startup → .shared → .whenNeeded → .weak → .transient
(가장 긴 생명주기)                    (가장 짧은 생명주기)
```

### **스코프 우선순위 (초기화 순서)**
```
.startup (0) → .shared (100) → .whenNeeded (200) → .weak (300) → .transient (400)
(먼저 초기화)                                                    (나중에 초기화)
```

### **초기화 시점**
- **즉시 초기화**: `.startup` (앱 시작 시)
- **지연 초기화**: 나머지 모든 스코프 (첫 사용 시)

---

## **스코프별 상세 가이드**

### **1. `.startup` 스코프**
> 🚀 **앱 시작 시 반드시 필요한 핵심 서비스**

**언제 사용하나요?**
- 앱 전체에서 사용되는 필수 서비스
- 초기화 시간이 오래 걸리는 서비스
- 다른 서비스들이 의존하는 기반 서비스

**특징:**
- ✅ 앱 시작 시 즉시 초기화
- ✅ 앱 종료까지 유지
- ✅ 가장 높은 우선순위
- ⚠️ 너무 많이 사용하면 앱 시작 속도 저하

**적합한 서비스:**
```swift
// ✅ 좋은 예시
struct LoggerServiceKey: DependencyKey {
    static var defaultValue: LoggerService { NoOpLogger() }
}

struct ConfigurationServiceKey: DependencyKey {
    static var defaultValue: ConfigurationService { 
        DefaultConfiguration() 
    }
}

struct DatabaseServiceKey: DependencyKey {
    static var defaultValue: DatabaseService { 
        InMemoryDatabase() 
    }
}

// 등록 예시
await builder.register(LoggerServiceKey.self, scope: .startup) { _ in
    ProductionLogger()
}
```

**❌ 부적합한 예시:**
```swift
// 사용자 프로필 서비스 - 로그인 후에만 필요
// 카메라 서비스 - 특정 화면에서만 사용
// 결제 서비스 - 구매 시에만 필요
```

### **2. `.shared` 스코프**
> 🔄 **여러 곳에서 공유되는 일반적인 서비스**

**언제 사용하나요?**
- 여러 화면/기능에서 공유되는 서비스
- 상태를 유지해야 하는 서비스
- 초기화 비용이 중간 정도인 서비스

**특징:**
- ✅ 첫 사용 시 초기화
- ✅ 앱 종료까지 유지 (또는 명시적 해제)
- ✅ 가장 일반적인 스코프
- ✅ 메모리와 성능의 균형

**적합한 서비스:**
```swift
// ✅ 좋은 예시
struct NetworkServiceKey: DependencyKey {
    static var defaultValue: NetworkService { 
        OfflineNetworkService() 
    }
}

struct UserSessionKey: DependencyKey {
    static var defaultValue: UserSession { 
        AnonymousSession() 
    }
}

struct CacheServiceKey: DependencyKey {
    static var defaultValue: CacheService { 
        InMemoryCache() 
    }
}

// 등록 예시
await builder.register(NetworkServiceKey.self, scope: .shared) { resolver in
    let logger = try await resolver.resolve(LoggerServiceKey.self)
    return HTTPNetworkService(logger: logger)
}
```

### **3. `.whenNeeded` 스코프**
> ⏰ **특정 상황에서만 필요한 서비스**

**언제 사용하나요?**
- 특정 기능/화면에서만 사용
- 초기화 비용이 높은 서비스
- 메모리 사용량이 큰 서비스

**특징:**
- ✅ 첫 사용 시 초기화
- ✅ 메모리 압박 시 자동 해제 가능
- ✅ 리소스 효율적
- ⚠️ 재초기화 비용 고려 필요

**적합한 서비스:**
```swift
// ✅ 좋은 예시
struct ImageProcessingServiceKey: DependencyKey {
    static var defaultValue: ImageProcessingService { 
        BasicImageProcessor() 
    }
}

struct LocationServiceKey: DependencyKey {
    static var defaultValue: LocationService { 
        MockLocationService() 
    }
}

struct VideoPlayerServiceKey: DependencyKey {
    static var defaultValue: VideoPlayerService { 
        DummyVideoPlayer() 
    }
}

// 등록 예시
await builder.register(ImageProcessingServiceKey.self, scope: .whenNeeded) { _ in
    // 무거운 이미지 처리 라이브러리 초기화
    AdvancedImageProcessor()
}
```

### **4. `.weak` 스코프**
> 🪶 **약한 참조로 관리되는 임시 서비스**

**언제 사용하나요?**
- 다른 객체의 생명주기에 의존하는 서비스
- 메모리 누수 방지가 중요한 서비스
- 임시적/일시적 서비스

**특징:**
- ✅ 약한 참조로 관리
- ✅ 참조하는 객체가 없으면 자동 해제
- ✅ 메모리 누수 방지
- ⚠️ 클래스 타입만 지원
- ⚠️ 예상치 못한 해제 가능성

**적합한 서비스:**
```swift
// ✅ 좋은 예시 - 클래스 타입만 가능
class ViewControllerCoordinator: Sendable {
    // 뷰 컨트롤러 간 네비게이션 관리
}

struct CoordinatorKey: DependencyKey {
    static var defaultValue: ViewControllerCoordinator { 
        DummyCoordinator() 
    }
}

// 등록 예시 - registerWeak 사용
await builder.registerWeak(CoordinatorKey.self) { _ in
    ViewControllerCoordinator()
}
```

### **5. `.transient` 스코프**
> 🔄 **매번 새로운 인스턴스가 필요한 서비스**

**언제 사용하나요?**
- 상태를 공유하면 안 되는 서비스
- 매번 새로운 인스턴스가 필요한 경우
- 가벼운 값 객체나 팩토리

**특징:**
- ✅ 매번 새로운 인스턴스 생성
- ✅ 상태 공유 없음
- ✅ 스레드 안전성 보장
- ⚠️ 초기화 비용이 누적됨

**적합한 서비스:**
```swift
// ✅ 좋은 예시
struct UUIDGeneratorKey: DependencyKey {
    static var defaultValue: UUIDGenerator { 
        SystemUUIDGenerator() 
    }
}

struct DateFormatterKey: DependencyKey {
    static var defaultValue: DateFormatter { 
        ISO8601DateFormatter() 
    }
}

// 등록 예시
await builder.register(UUIDGeneratorKey.self, scope: .transient) { _ in
    SystemUUIDGenerator() // 매번 새로운 인스턴스
}
```

---

## **스코프 선택 결정 트리**

```
의존성을 등록하려고 하나요?
│
├─ 앱 시작 시 반드시 필요한가요?
│  └─ YES → .startup
│
├─ 여러 곳에서 상태를 공유해야 하나요?
│  ├─ YES → 메모리 사용량이 큰가요?
│  │  ├─ YES → .whenNeeded
│  │  └─ NO → .shared
│  │
│  └─ NO → 매번 새로운 인스턴스가 필요한가요?
│     ├─ YES → .transient
│     └─ NO → 생명주기가 다른 객체에 의존하나요?
│        ├─ YES → .weak
│        └─ NO → .shared
```

---

## **실전 예시**

### **전형적인 iOS 앱의 스코프 구성**

```swift
// AppModule.swift
struct AppModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        // 🚀 .startup - 앱 핵심 서비스
        await builder.register(LoggerServiceKey.self, scope: .startup) { _ in
            ProductionLogger()
        }
        
        await builder.register(ConfigurationServiceKey.self, scope: .startup) { _ in
            AppConfiguration()
        }
        
        await builder.register(DatabaseServiceKey.self, scope: .startup) { resolver in
            let config = try await resolver.resolve(ConfigurationServiceKey.self)
            return CoreDataService(config: config)
        }
        
        // 🔄 .shared - 공통 서비스
        await builder.register(NetworkServiceKey.self, scope: .shared) { resolver in
            let logger = try await resolver.resolve(LoggerServiceKey.self)
            return HTTPNetworkService(logger: logger)
        }
        
        await builder.register(UserSessionKey.self, scope: .shared) { resolver in
            let database = try await resolver.resolve(DatabaseServiceKey.self)
            return UserSessionService(database: database)
        }
        
        // ⏰ .whenNeeded - 특수 기능
        await builder.register(CameraServiceKey.self, scope: .whenNeeded) { _ in
            AVCameraService()
        }
        
        await builder.register(LocationServiceKey.self, scope: .whenNeeded) { _ in
            CoreLocationService()
        }
        
        // 🪶 .weak - 임시 서비스
        await builder.registerWeak(NavigationCoordinatorKey.self) { _ in
            NavigationCoordinator()
        }
        
        // 🔄 .transient - 유틸리티
        await builder.register(UUIDGeneratorKey.self, scope: .transient) { _ in
            SystemUUIDGenerator()
        }
    }
}
```

### **의존성 관계 명시적 선언**

```swift
// 의존성 관계를 명확히 선언하여 빌드 타임 검증 활용
await builder
    .declareDependency(NetworkServiceKey.self, dependsOn: LoggerServiceKey.self)
    .declareDependency(UserSessionKey.self, dependsOn: DatabaseServiceKey.self)
    .declareDependencies(
        CameraServiceKey.self,
        dependsOn: [LoggerServiceKey.self, UserSessionKey.self]
    )
```

---

## **성능 최적화 팁**

### **1. 앱 시작 성능 최적화**

```swift
// ❌ 나쁜 예시 - 너무 많은 .startup 스코프
await builder.register(HeavyServiceKey.self, scope: .startup) { _ in
    HeavyService() // 앱 시작 지연
}

// ✅ 좋은 예시 - 필요할 때 로딩
await builder.register(HeavyServiceKey.self, scope: .whenNeeded) { _ in
    HeavyService()
}
```

### **2. 메모리 효율성 최적화**

```swift
// ✅ 메모리 압박 시 해제 가능한 서비스
await builder.register(ImageCacheKey.self, scope: .whenNeeded) { _ in
    LargeImageCache() // 메모리 부족 시 자동 해제
}

// ✅ 약한 참조로 메모리 누수 방지
await builder.registerWeak(TemporaryServiceKey.self) { _ in
    TemporaryService()
}
```

### **3. 스코프 호환성 확인**

```swift
// ✅ 스코프 호환성 준수
// .startup 서비스는 .shared 서비스에 의존 가능
await builder.register(SharedServiceKey.self, scope: .shared) { resolver in
    let startupService = try await resolver.resolve(StartupServiceKey.self)
    return SharedService(startup: startupService)
}

// ❌ 스코프 호환성 위반 - 빌드 타임에 감지됨
// .startup 서비스가 .shared 서비스에 의존하면 에러
```

---

## **안티패턴과 해결책**

### **❌ 안티패턴 1: 모든 것을 .startup으로**

```swift
// 문제: 앱 시작 속도 저하
await builder.register(CameraServiceKey.self, scope: .startup) { _ in
    CameraService() // 카메라 기능이 필요하지 않은데도 초기화
}
```

**✅ 해결책:**
```swift
await builder.register(CameraServiceKey.self, scope: .whenNeeded) { _ in
    CameraService() // 카메라 기능 사용 시에만 초기화
}
```

### **❌ 안티패턴 2: 무분별한 .transient 사용**

```swift
// 문제: 불필요한 초기화 비용
await builder.register(ExpensiveServiceKey.self, scope: .transient) { _ in
    ExpensiveService() // 매번 비싼 초기화 비용
}
```

**✅ 해결책:**
```swift
await builder.register(ExpensiveServiceKey.self, scope: .shared) { _ in
    ExpensiveService() // 한 번만 초기화하고 재사용
}
```

### **❌ 안티패턴 3: 스코프 호환성 무시**

```swift
// 문제: 런타임 에러 가능성
await builder.register(StartupServiceKey.self, scope: .startup) { resolver in
    // .startup이 .whenNeeded에 의존 - 초기화 순서 문제
    let whenNeededService = try await resolver.resolve(WhenNeededServiceKey.self)
    return StartupService(dependency: whenNeededService)
}
```

**✅ 해결책:**
```swift
// 의존성 방향을 올바르게 설정
await builder.register(WhenNeededServiceKey.self, scope: .whenNeeded) { resolver in
    let startupService = try await resolver.resolve(StartupServiceKey.self)
    return WhenNeededService(startup: startupService)
}
```

### **❌ 안티패턴 4: .weak 스코프 오남용**

```swift
// 문제: 예상치 못한 해제로 인한 크래시
await builder.registerWeak(CriticalServiceKey.self) { _ in
    CriticalService() // 중요한 서비스가 예상치 못하게 해제될 수 있음
}
```

**✅ 해결책:**
```swift
await builder.register(CriticalServiceKey.self, scope: .shared) { _ in
    CriticalService() // 안정적인 생명주기 보장
}
```

---

## **스코프 마이그레이션 가이드**

기존 코드에서 스코프를 변경할 때의 체크리스트:

### **1. .startup으로 변경 시**
- [ ] 앱 시작 시 반드시 필요한가?
- [ ] 초기화 시간이 앱 시작 속도에 미치는 영향은?
- [ ] 다른 서비스들의 의존성 체인 확인

### **2. .whenNeeded로 변경 시**
- [ ] 메모리 해제 시 재초기화 비용 확인
- [ ] 의존하는 다른 서비스들의 영향 분석
- [ ] 사용 패턴 분석 (자주 사용되는가?)

### **3. .weak로 변경 시**
- [ ] 클래스 타입인가?
- [ ] 예상치 못한 해제가 문제가 되지 않는가?
- [ ] 생명주기를 관리하는 강한 참조가 있는가?

---

이 가이드라인을 따르면 Weaver의 스코프 시스템을 최대한 활용하여 성능과 메모리 효율성을 모두 확보할 수 있습니다.