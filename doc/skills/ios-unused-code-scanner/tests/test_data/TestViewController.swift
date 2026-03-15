// TestViewController.swift
// 测试数据 - Swift文件示例

import UIKit

class TestViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    func setupUI() {
        view.backgroundColor = .white
    }
}

// 这个类未被使用
class UnusedSwiftClass {
    func unusedMethod() {
        print("This method is never called")
    }
}
