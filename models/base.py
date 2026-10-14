# model/base.py
''''''
'''
所有ORM模型的共同父类
DeclarativeBase是 SQLAlchemy 2.x 推荐的声明式基类。所有表模型都继承它，SQLAlchemy 才能统一管理它们的元数据。
'''


from sqlalchemy.orm import DeclarativeBase

class Base(DeclarativeBase):
    pass