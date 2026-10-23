/// 纯逻辑放在不依赖 UI 的类型里，方便单元测试。
struct Counter {
    private(set) var value = 0

    mutating func increment() { value += 1 }

    mutating func decrement() { value = max(0, value - 1) }
}
