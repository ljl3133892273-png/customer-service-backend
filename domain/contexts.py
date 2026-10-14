''''''
'''
对话上下文模型

序列化:
使用pydantic的obj.model_dump(mode='json')和cls.model_validate(data)做数据类型转换
|方法                        | 作用                  | 形象比喻                        |
|---------------------------| ---------------------| ------------------------------ |
|obj.model_dump(mode='json')| 把 Python 对象变成字典  | **打包**：把行李装进箱子，准备入库   |
|cls.model_validate(data)   | 把字典还原成 Python 对象 | **拆包**：从箱子里取出行李，恢复原样 |
'''
from pydantic import BaseModel


class TaskContext(BaseModel):
    """
    业务任务上下文
    """
    flow_id: str  # 业务任务的流程ID
    step_id: str | None = None  # 业务任务下的步骤ID
    slots: dict = {}  # 业务任务执行过程中收集到的槽位数据


# SystemContext 的基础结构与 TaskContext 相同，同样记录流程标识和当前步骤。
class SystemContext(BaseModel):
    """
    系统流程上下文
    定义具体流程的通用属性
    """
    flow_id: str  # 系统流程的流程ID
    step_id: str | None = None  # 系统流程当前执行的步骤ID


# 任务刚开始
class StartedSystemContext(SystemContext):
    """
    流程开始
    """
    started_flow_id: str = ""  # 新开始的业务任务ID
    started_flow_name: str = ""  # 新开始的业务任务名字


'''
任务被中断 有两种典型场景
1.打断一个任务(基础)
状态快照
- 老的退款任务先放着（用 `interrupted_flow_name`）
- 现在开始处理新的物流查询任务（用 `started_flow_name`）
2.打断两个任务(连环打断)
'''


# 任务被打断
class InterruptedSystemContext(SystemContext):
    """
    流程中断
    """
    interrupted_flow_id: str = ""  # 被中断的旧业务任务ID
    interrupted_flow_name: str = ""  # 被中断的旧业务任务名字
    started_flow_id: str = ""  # 新开始的业务任务ID
    started_flow_name: str = ""  # 新开始的业务任务名字


'''
任务取消有两种典型场景，对应用户两种不同的说法
1.取消当前活跃任务
2.取消挂起的任务
'''


# 任务被取消 被取消的退款不会进入 `paused_tasks`,而是直接丢弃。这是和"打断"最根本的区别。
class CanceledSystemContext(SystemContext):
    """
    流程取消
    """
    canceled_flow_id: str = ""  # 被取消的业务任务ID
    canceled_flow_name: str = ""  # 被取消的业务任务名字


'''
恢复任务有两种典型场景,对应用户两种不同的说法:
1.默认恢复(用户没指明恢复哪个) -> 回复最近挂起的任务(LIFO 语义——**后进先出**。)
2.精确恢复(用户明确指明)
'''


# 任务恢复
class ResumedSystemContext(SystemContext):
    """
    流程恢复
    """
    resumed_flow_id: str = ""  # 被恢复的业务任务ID
    resumed_flow_name: str = ""  # 被恢复的业务任务名字


'''
|        | 前四个                              | CollectSystemContext       |
| ------ | ---------------------------------- | -------------------------- |
| 触发原因 | 任务的生命周期事件（开始/打断/取消/恢复） | 业务任务主动声明"我需要这个槽位" |
| 出现频率 | 任务切换时可能会出现                  | 每次需要补槽都会出现           |
| 携带数据 | 业务流程名字                        | 槽位名 + 提示文案             |
'''


# 收集槽位
class CollectedSystemContext(SystemContext):
    """
    系统流程收集槽位信息
    """
    slot_name: str = ""  # 收集的槽位名
    response: dict = {}  # 例如：{"text":"请告诉我你的订单号"}


if __name__ == '__main__':
    pass
