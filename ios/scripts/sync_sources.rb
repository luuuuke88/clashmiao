#!/usr/bin/env ruby
# 把 Swift 源文件登记进 Runner.xcodeproj（工程是 objectVersion=54，没有按目录自动同步）。
#
# 用法（在仓库根目录）：
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/<版本>/libexec ruby ios/scripts/sync_sources.rb
#
# 行为：对下面 MANIFEST 里的每个文件，确保它在工程里有文件引用，并且属于列出的 target
# 的 Sources build phase；MANIFEST 里已不存在于磁盘的文件会被移出工程（引用与 build file 一并删除）。
# 幂等：重复运行不产生变化。
require 'xcodeproj'
require 'pathname'

IOS = File.expand_path('..', __dir__)
PROJECT = File.join(IOS, 'Runner.xcodeproj')

R = 'Runner'
X = 'SingBoxPacketTunnel'
T = 'RunnerTests'

# 路径相对 ios/；值是该文件要加入的 target。
# 测试 target 通过 TEST_HOST + `@testable import Runner` 使用主 App 的符号，不重复编译被测源码
# （重复编译会让同名类型在测试里二义）；纯 Foundation 的 Shared 文件因此也要进 Runner。
MANIFEST = {
  # Shared（Runner + 扩展）
  'Shared/Kernel/KernelIntent.swift' => [R, X],
  'Shared/Kernel/ExtensionState.swift' => [R, X],
  'Shared/Kernel/ExtensionStateWriter.swift' => [R, X],
  # Runner 协调器
  'Runner/Kernel/CoordinatorModel.swift' => [R],
  'Runner/Kernel/CoordinatorCore.swift' => [R],
  'Runner/Kernel/ConfigBuilder.swift' => [R],
  'Runner/Kernel/KernelStore.swift' => [R],
  'Runner/Kernel/TunnelAdapter.swift' => [R],
  'Runner/Kernel/KernelExecutor.swift' => [R],
  'Runner/Kernel/KernelCoordinator.swift' => [R],
  'Runner/Kernel/TunnelController.swift' => [R],
  'Runner/Kernel/KernelHost.swift' => [R],
  'Runner/Handlers/KernelSnapshotStream.swift' => [R],
  'Runner/Handlers/NetworkStream.swift' => [R],
  # 测试
  'RunnerTests/CoordinatorCoreTests.swift' => [T],
  'RunnerTests/ConfigBuilderTests.swift' => [T],
  'RunnerTests/KernelContractTests.swift' => [T],
  'RunnerTests/KernelCoordinatorTests.swift' => [T],
  'RunnerTests/ExtensionStateWriterTests.swift' => [T],
  'RunnerTests/PigeonParityTests.swift' => [T],
}.freeze

# 已从磁盘删除、需要移出工程的文件。
REMOVED = %w[
  Runner/VPN/TunnelManager.swift
  SingBoxPacketTunnel/TrafficStats.swift
  SingBoxPacketTunnel/Kernel/KernelEngine.swift
].freeze

project = Xcodeproj::Project.open(PROJECT)
targets = project.targets.to_h { |t| [t.name, t] }

def group_for(project, rel_dir)
  group = project.main_group
  rel_dir.split('/').each do |part|
    group = group[part] || group.new_group(part, part)
  end
  group
end

changed = false

MANIFEST.each do |rel, names|
  abs = File.join(IOS, rel)
  next unless File.exist?(abs) # 还没创建的文件先跳过，等后续任务落地后再跑一遍

  dir = File.dirname(rel)
  ref = project.files.find { |f| f.real_path.to_s == abs }
  if ref.nil?
    group = group_for(project, dir)
    ref = group.new_reference(File.basename(rel))
    changed = true
  end
  names.each do |name|
    phase = targets.fetch(name).source_build_phase
    next if phase.files_references.include?(ref)

    phase.add_file_reference(ref)
    changed = true
  end
end

REMOVED.each do |rel|
  abs = File.join(IOS, rel)
  next if File.exist?(abs)

  ref = project.files.find { |f| f.real_path.to_s == abs }
  next if ref.nil?

  targets.each_value do |t|
    t.source_build_phase.files.select { |bf| bf.file_ref == ref }.each do |bf|
      bf.remove_from_project
      changed = true
    end
  end
  ref.remove_from_project
  changed = true
end

if changed
  project.save
  puts 'Runner.xcodeproj updated'
else
  puts 'Runner.xcodeproj already up to date'
end
