package com.dawndrizzle.wing.cqut.widgetbridge

import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files
import java.time.Instant
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class DiagnosticFileStoreTest {
  private val start = Instant.parse("2026-10-08T12:00:00Z").toEpochMilli()
  private fun line(now: Long, index: Int = 0, text: String = "失败".repeat(1900)) = DiagnosticJson.encode(mapOf("timestamp" to Instant.ofEpochMilli(now).toString(), "message" to text, "sequence" to index))

  @Test
  fun `all sources retain fixed slots including current and preserve complete unicode records`() {
    val root = Files.createTempDirectory("diagnostic-capacity").toFile()
    try {
      val store = DiagnosticFileStore(root) { start }
      for (source in DiagnosticFileStore.capacities.keys) repeat(150) { assertTrue(store.write(source, line(start, it))) }
      assertEquals(8, store.stats()["files"])
      assertTrue((store.stats()["bytes"] as Long) <= 2 * 1024 * 1024)
      assertTrue(root.listFiles()!!.all { it.length() <= DiagnosticFileStore.FILE_BYTES })
      assertTrue(store.snapshotLines().all { it.endsWith("}") && it.contains("失败") })
      assertFalse(store.write("native", line(start, text = "字".repeat(6000))))
    } finally { root.deleteRecursively() }
  }

  @Test
  fun `concurrent writers serialize rotation and snapshot without partial records`() {
    val root = Files.createTempDirectory("diagnostic-concurrent").toFile()
    val pool = Executors.newFixedThreadPool(5)
    try {
      val store = DiagnosticFileStore(root) { start }
      val futures = (0 until 4).map { worker -> pool.submit { repeat(150) { assertTrue(store.write("native", line(start, worker * 1000 + it))); assertTrue(store.snapshotLines().all { entry -> entry.endsWith("}") }) } } }
      pool.shutdown()
      assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS))
      futures.forEach { it.get() }
      assertTrue((store.stats()["bytes"] as Long) <= 512 * 1024)
      assertTrue(store.snapshotLines().all { it.endsWith("}") })
    } finally { pool.shutdownNow(); root.deleteRecursively() }
  }

  @Test
  fun `day rotation restart and retention prune old event times even inside a mixed file`() {
    val root = Files.createTempDirectory("diagnostic-retention").toFile()
    var now = start
    try {
      val store = DiagnosticFileStore(root) { now }
      store.write("native", line(now, 0))
      now += 24 * 60 * 60 * 1000L
      store.write("native", line(now, 1))
      assertEquals(2, store.stats()["files"])
      val restart = DiagnosticFileStore(root) { now }
      assertEquals(2, restart.snapshotLines().size)
      now += 3 * 24 * 60 * 60 * 1000L + 1
      restart.prune()
      assertTrue(restart.snapshotLines().isEmpty())
      assertEquals(0, restart.stats()["files"])
      val current = root.resolve("native-0.jsonl")
      current.writeText(line(now - DiagnosticFileStore.RETENTION_MILLIS - 1, 0, "old") + "\n" + line(now - DiagnosticFileStore.RETENTION_MILLIS + 1, 1, "new") + "\n")
      current.setLastModified(now - DiagnosticFileStore.RETENTION_MILLIS + 1)
      assertEquals(1, restart.snapshotLines().size)
      assertFalse(current.readText().contains("old"))
    } finally { root.deleteRecursively() }
  }

  @Test
  fun `bounded encoding counts escaped bytes prioritizes stack and keeps newest context`() {
    val stack = "堆栈\n".repeat(1800)
    val encoded = DiagnosticJson.bounded(mapOf("timestamp" to Instant.ofEpochMilli(start).toString(), "message" to "错误".repeat(9000), "stackTrace" to stack, "context" to (0..63).map { mapOf("message" to "线索$it".repeat(400)) }))
    assertTrue(encoded.toByteArray(Charsets.UTF_8).size + 1 <= 16 * 1024)
    assertTrue(encoded.contains("堆栈"))
    assertTrue(encoded.contains("truncated"))
    assertTrue(encoded.contains("线索63"))
  }
}
