# knowledge/intents.py


from pydantic import BaseModel


class KnowledgeIntent(BaseModel):
    id: str  # 意图唯一标识，如 `product_info`
    description: str  # 意图的中文说明，喂给 LLM 帮它分类
    provider_ids: list[str] = []  # 意图要查哪些知识源
    requires_object: str | None = None  # 意图是否必须依附一个聚焦对象


KNOWLEDGE_INTENTS: dict[str, KnowledgeIntent] = {
    "product_info": KnowledgeIntent(
        id="product_info",
        description="商品信息咨询",
        provider_ids=["api.product"],
        requires_object="product",
    ),
    "order_info": KnowledgeIntent(
        id="order_info",
        description="订单信息咨询",
        provider_ids=["api.order"],
        requires_object="order",
    ),
    "refund_policy": KnowledgeIntent(
        id="refund_policy",
        description="退款政策咨询",
        provider_ids=["faq.default", "rag.default"],
    ),
    "return_policy": KnowledgeIntent(
        id="return_policy",
        description="退货政策咨询",
        provider_ids=["faq.default", "rag.default"],
    ),
    "shipping_policy": KnowledgeIntent(
        id="shipping_policy",
        description="配送政策咨询",
        provider_ids=["faq.default", "rag.default"],
    ),
    "platform_rule": KnowledgeIntent(
        id="platform_rule",
        description="平台规则咨询",
        provider_ids=["rag.default"],
    ),
    "general_product_info": KnowledgeIntent(
        id="general_product_info",
        description="商品与选材通用咨询",
        provider_ids=["faq.default", "rag.default"],
    ),
}
