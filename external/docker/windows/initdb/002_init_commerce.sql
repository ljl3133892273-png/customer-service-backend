SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS `commerce`
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE `commerce`;

CREATE TABLE IF NOT EXISTS `users` (
  `id` BIGINT PRIMARY KEY AUTO_INCREMENT,
  `user_id` VARCHAR(64) NOT NULL UNIQUE,
  `nickname` VARCHAR(100) NOT NULL,
  `level` VARCHAR(32) NOT NULL,
  `mobile_masked` VARCHAR(32) NOT NULL,
  `created_at` DATETIME NOT NULL
) ENGINE=INNODB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `products` (
  `id` BIGINT PRIMARY KEY AUTO_INCREMENT,
  `product_id` VARCHAR(64) NOT NULL UNIQUE,
  `title` VARCHAR(255) NOT NULL,
  `description` TEXT NOT NULL,
  `price` DECIMAL(10, 2) NOT NULL,
  `stock_status` VARCHAR(32) NOT NULL,
  `cover_url` VARCHAR(500) NULL,
  `attributes_json` JSON NOT NULL,
  `created_at` DATETIME NOT NULL
) ENGINE=INNODB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `orders` (
  `id` BIGINT PRIMARY KEY AUTO_INCREMENT,
  `order_id` VARCHAR(64) NOT NULL UNIQUE,
  `user_id` BIGINT NOT NULL,
  `status` VARCHAR(32) NOT NULL,
  `status_desc` VARCHAR(255) NOT NULL,
  `amount` DECIMAL(10, 2) NOT NULL,
  `created_at` DATETIME NOT NULL,
  `receiver_name` VARCHAR(64) NOT NULL,
  `receiver_phone_masked` VARCHAR(32) NOT NULL,
  `receiver_address` VARCHAR(255) NOT NULL,
  CONSTRAINT `fk_orders_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=INNODB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `order_items` (
  `id` BIGINT PRIMARY KEY AUTO_INCREMENT,
  `order_id` BIGINT NOT NULL,
  `product_id` BIGINT NOT NULL,
  `title_snapshot` VARCHAR(255) NOT NULL,
  `quantity` INT NOT NULL,
  `price` DECIMAL(10, 2) NOT NULL,
  CONSTRAINT `fk_order_items_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`),
  CONSTRAINT `fk_order_items_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`)
) ENGINE=INNODB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `logistics_records` (
  `id` BIGINT PRIMARY KEY AUTO_INCREMENT,
  `order_id` BIGINT NOT NULL,
  `logistics_company` VARCHAR(64) NOT NULL,
  `tracking_number` VARCHAR(64) NOT NULL,
  `status` VARCHAR(32) NOT NULL,
  `status_desc` VARCHAR(255) NOT NULL,
  `updated_at` DATETIME NOT NULL,
  CONSTRAINT `fk_logistics_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`)
) ENGINE=INNODB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `logistics_traces` (
  `id` BIGINT PRIMARY KEY AUTO_INCREMENT,
  `logistics_record_id` BIGINT NOT NULL,
  `trace_time` DATETIME NOT NULL,
  `trace_desc` VARCHAR(255) NOT NULL,
  CONSTRAINT `fk_logistics_traces_record` FOREIGN KEY (`logistics_record_id`) REFERENCES `logistics_records` (`id`)
) ENGINE=INNODB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `refund_requests` (
  `id` BIGINT PRIMARY KEY AUTO_INCREMENT,
  `refund_id` VARCHAR(64) NOT NULL UNIQUE,
  `order_id` BIGINT NOT NULL,
  `operator` VARCHAR(64) NOT NULL,
  `reason` VARCHAR(255) NOT NULL,
  `status` VARCHAR(32) NOT NULL,
  `status_desc` VARCHAR(255) NOT NULL,
  `created_at` DATETIME NOT NULL,
  CONSTRAINT `fk_refund_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`)
) ENGINE=INNODB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `shipping_urge_requests` (
  `id` BIGINT PRIMARY KEY AUTO_INCREMENT,
  `urge_id` VARCHAR(64) NOT NULL UNIQUE,
  `order_id` BIGINT NOT NULL,
  `operator` VARCHAR(64) NOT NULL,
  `reason` VARCHAR(255) NOT NULL,
  `status` VARCHAR(32) NOT NULL,
  `status_desc` VARCHAR(255) NOT NULL,
  `created_at` DATETIME NOT NULL,
  CONSTRAINT `fk_urge_order` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`)
) ENGINE=INNODB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `users` (`user_id`, `nickname`, `level`, `mobile_masked`, `created_at`) VALUES
  ('u1001', '小李', 'PLUS', '138****1234', '2026-04-01 09:00:00'),
  ('u1002', '王敏', '普通会员', '139****5678', '2026-04-02 10:30:00'),
  ('u1003', '陈晨', 'PLUS', '137****2468', '2026-04-03 19:20:00');

INSERT INTO `products` (`product_id`, `title`, `description`, `price`, `stock_status`, `cover_url`, `attributes_json`, `created_at`) VALUES
  (
    'SKU10001',
    '云岩灰 亮光抛釉砖 800×800',
    '通体坯体、亮光釉面，灰度均匀不显脏，适合客厅餐厅大面积铺贴；建议留缝 1.5~2mm，配 2mm 十字定位器。',
    68.00,
    '有货',
    '/tiles/tile-01-polished-grey.jpg',
    JSON_OBJECT('规格', '800×800', '表面工艺', '亮光抛釉', '色系', '灰色', '色号', 'YG-8027', '批号', 'B2609', '每箱片数', '3', '单片面积', '0.64㎡', '吸水率', '≤0.5%', '防滑等级', 'R9', '适用空间', '客厅/餐厅'),
    '2026-03-20 12:00:00'
  ),
  (
    'SKU10002',
    '卡拉拉白 通体大理石瓷砖 800×800',
    '卡拉拉白纹理通透自然，坯体与表面同色，切割后侧边不露白；适合客厅与电视背景墙。',
    118.00,
    '有货',
    '/tiles/tile-02-marble-white.jpg',
    JSON_OBJECT('规格', '800×800', '表面工艺', '通体全抛', '色系', '白色', '色号', 'KL-8021', '批号', 'B2611', '每箱片数', '3', '单片面积', '0.64㎡', '吸水率', '≤0.5%', '防滑等级', 'R9', '适用空间', '客厅/背景墙'),
    '2026-03-22 14:00:00'
  ),
  (
    'SKU10003',
    '奶咖杏 柔光砖 600×600',
    '柔光釉面不反光、脚感温和，防滑等级 R10；适合卧室、厨房与卫生间干区，配美缝剂效果更佳。',
    42.00,
    '有货',
    '/tiles/tile-03-soft-cream.jpg',
    JSON_OBJECT('规格', '600×600', '表面工艺', '柔光哑面', '色系', '米杏色', '色号', 'NK-6033', '批号', 'B2607', '每箱片数', '4', '单片面积', '0.36㎡', '吸水率', '≤0.5%', '防滑等级', 'R10', '适用空间', '卧室/厨卫'),
    '2026-03-25 08:30:00'
  ),
  (
    'SKU10004',
    '金丝胡桃 木纹砖 200×1200',
    '1:6 木纹比例接近实木地板，哑光防滑 R11；适合卧室、阳台与地暖房，建议工字铺或人字铺。',
    39.00,
    '有货',
    '/tiles/tile-04-wood-walnut.jpg',
    JSON_OBJECT('规格', '200×1200', '表面工艺', '仿木纹哑光', '色系', '胡桃木色', '色号', 'MW-1225', '批号', 'B2605', '每箱片数', '6', '单片面积', '0.24㎡', '吸水率', '≤0.5%', '防滑等级', 'R11', '适用空间', '卧室/阳台'),
    '2026-03-27 11:10:00'
  ),
  (
    'SKU10005',
    '雪山白 岩板 900×1800',
    '大规格连纹岩板，耐磨耐高温、可直接接触食物；多用于电视背景墙、餐边柜台面与岛台，需提前预约加工。',
    680.00,
    '有货',
    '/tiles/tile-05-sintered-white.jpg',
    JSON_OBJECT('规格', '900×1800', '表面工艺', '亮面岩板', '色系', '白色', '色号', 'YB-1892', '批号', 'B2612', '每箱片数', '1', '单片面积', '1.62㎡', '吸水率', '≤0.05%', '防滑等级', 'R9', '适用空间', '背景墙/台面'),
    '2026-03-29 16:20:00'
  ),
  (
    'SKU10006',
    '手作砂岩 仿古砖 600×600',
    '手作质感仿古砖，表面微凹凸防滑 R11，吸水率偏高需做防污处理；适合庭院、露台与厨卫地面。',
    55.00,
    '有货',
    '/tiles/tile-06-antique-sand.jpg',
    JSON_OBJECT('规格', '600×600', '表面工艺', '哑光仿古', '色系', '砂岩米黄', '色号', 'FG-6048', '批号', 'B2603', '每箱片数', '4', '单片面积', '0.36㎡', '吸水率', '≤3%', '防滑等级', 'R11', '适用空间', '庭院/厨卫'),
    '2026-03-30 13:40:00'
  );

INSERT INTO `orders` (
  `order_id`, `user_id`, `status`, `status_desc`, `amount`, `created_at`, `receiver_name`, `receiver_phone_masked`, `receiver_address`
) VALUES
  (
    'A20260410001',
    (SELECT `id` FROM `users` WHERE `user_id` = 'u1001'),
    '待发货',
    '仓储部正在核对色号与批次，预计 24 小时内安排大件发出。',
    2856.00,
    '2026-04-10 10:00:00',
    '李先生',
    '138****1234',
    '上海市浦东新区世纪大道 100 号'
  ),
  (
    'A20260408002',
    (SELECT `id` FROM `users` WHERE `user_id` = 'u1001'),
    '运输中',
    '货物已发出，正在大件物流配送途中，到货后请开箱验收破损情况。',
    3540.00,
    '2026-04-08 15:30:00',
    '李先生',
    '138****1234',
    '上海市浦东新区世纪大道 100 号'
  ),
  (
    'A20260405003',
    (SELECT `id` FROM `users` WHERE `user_id` = 'u1001'),
    '已完成',
    '订单已签收完成，开箱验收无破损。',
    840.00,
    '2026-04-05 11:20:00',
    '李先生',
    '138****1234',
    '上海市浦东新区世纪大道 100 号'
  ),
  (
    'A20260407004',
    (SELECT `id` FROM `users` WHERE `user_id` = 'u1001'),
    '待揽收',
    '仓储部已打包完成并核对批号，等待物流上门揽收。',
    2340.00,
    '2026-04-07 18:15:00',
    '李先生',
    '138****1234',
    '上海市浦东新区世纪大道 100 号'
  ),
  (
    'A20260402005',
    (SELECT `id` FROM `users` WHERE `user_id` = 'u1001'),
    '已取消',
    '订单已取消，款项将在 1-3 个工作日内原路退回。',
    680.00,
    '2026-04-02 09:45:00',
    '李先生',
    '138****1234',
    '上海市浦东新区世纪大道 100 号'
  ),
  (
    'B20260409001',
    (SELECT `id` FROM `users` WHERE `user_id` = 'u1002'),
    '运输中',
    '货物已从佛山仓发出，正在大件物流运输途中。',
    1320.00,
    '2026-04-09 20:30:00',
    '王女士',
    '139****5678',
    '杭州市西湖区文三路 88 号'
  ),
  (
    'B20260401002',
    (SELECT `id` FROM `users` WHERE `user_id` = 'u1002'),
    '已完成',
    '订单已签收完成，其中 3 片边角磕碰已登记售后。',
    944.00,
    '2026-04-01 14:05:00',
    '王女士',
    '139****5678',
    '杭州市西湖区文三路 88 号'
  ),
  (
    'C20260406001',
    (SELECT `id` FROM `users` WHERE `user_id` = 'u1003'),
    '待发货',
    '仓储部正在备货，预计明日安排发出。',
    2040.00,
    '2026-04-06 12:25:00',
    '陈先生',
    '137****2468',
    '北京市朝阳区建国路 56 号'
  );

INSERT INTO `order_items` (`order_id`, `product_id`, `title_snapshot`, `quantity`, `price`) VALUES
  (
    (SELECT `id` FROM `orders` WHERE `order_id` = 'A20260410001'),
    (SELECT `id` FROM `products` WHERE `product_id` = 'SKU10001'),
    '云岩灰 亮光抛釉砖 800×800',
    42,
    68.00
  ),
  (
    (SELECT `id` FROM `orders` WHERE `order_id` = 'A20260408002'),
    (SELECT `id` FROM `products` WHERE `product_id` = 'SKU10002'),
    '卡拉拉白 通体大理石瓷砖 800×800',
    30,
    118.00
  ),
  (
    (SELECT `id` FROM `orders` WHERE `order_id` = 'A20260405003'),
    (SELECT `id` FROM `products` WHERE `product_id` = 'SKU10003'),
    '奶咖杏 柔光砖 600×600',
    20,
    42.00
  ),
  (
    (SELECT `id` FROM `orders` WHERE `order_id` = 'A20260407004'),
    (SELECT `id` FROM `products` WHERE `product_id` = 'SKU10004'),
    '金丝胡桃 木纹砖 200×1200',
    60,
    39.00
  ),
  (
    (SELECT `id` FROM `orders` WHERE `order_id` = 'A20260402005'),
    (SELECT `id` FROM `products` WHERE `product_id` = 'SKU10005'),
    '雪山白 岩板 900×1800',
    1,
    680.00
  ),
  (
    (SELECT `id` FROM `orders` WHERE `order_id` = 'B20260409001'),
    (SELECT `id` FROM `products` WHERE `product_id` = 'SKU10006'),
    '手作砂岩 仿古砖 600×600',
    24,
    55.00
  ),
  (
    (SELECT `id` FROM `orders` WHERE `order_id` = 'B20260401002'),
    (SELECT `id` FROM `products` WHERE `product_id` = 'SKU10002'),
    '卡拉拉白 通体大理石瓷砖 800×800',
    8,
    118.00
  ),
  (
    (SELECT `id` FROM `orders` WHERE `order_id` = 'C20260406001'),
    (SELECT `id` FROM `products` WHERE `product_id` = 'SKU10005'),
    '雪山白 岩板 900×1800',
    3,
    680.00
  );

INSERT INTO `logistics_records` (
  `order_id`, `logistics_company`, `tracking_number`, `status`, `status_desc`, `updated_at`
) VALUES
  (
    (SELECT `id` FROM `orders` WHERE `order_id` = 'A20260408002'),
    '京东大件',
    'JD000123456789',
    '运输中',
    '货物已到达上海大件分拨中心，正在安排送货上门。',
    '2026-04-10 09:00:00'
  ),
  (
    (SELECT `id` FROM `orders` WHERE `order_id` = 'A20260405003'),
    '京东大件',
    'JD000987654321',
    '已签收',
    '货物已签收，客户开箱验收无破损。',
    '2026-04-06 18:30:00'
  ),
  (
    (SELECT `id` FROM `orders` WHERE `order_id` = 'B20260409001'),
    '德邦物流',
    'DB0005566778899',
    '派送中',
    '货物已到达杭州派送网点，正在安排大件派送。',
    '2026-04-11 08:40:00'
  );

INSERT INTO `logistics_traces` (`logistics_record_id`, `trace_time`, `trace_desc`) VALUES
  (
    (SELECT `id` FROM `logistics_records` WHERE `tracking_number` = 'JD000123456789'),
    '2026-04-10 09:00:00',
    '货物已到达上海大件分拨中心，正在安排送货上门。'
  ),
  (
    (SELECT `id` FROM `logistics_records` WHERE `tracking_number` = 'JD000123456789'),
    '2026-04-09 19:30:00',
    '货物已从苏州分拨中心发出。'
  ),
  (
    (SELECT `id` FROM `logistics_records` WHERE `tracking_number` = 'JD000123456789'),
    '2026-04-09 11:20:00',
    '佛山仓已完成出库与批号核对，京东大件已揽收。'
  ),
  (
    (SELECT `id` FROM `logistics_records` WHERE `tracking_number` = 'JD000987654321'),
    '2026-04-06 18:30:00',
    '货物已签收，客户开箱验收无破损。'
  ),
  (
    (SELECT `id` FROM `logistics_records` WHERE `tracking_number` = 'JD000987654321'),
    '2026-04-06 10:00:00',
    '配送员已联系客户，约定送货上门时间。'
  ),
  (
    (SELECT `id` FROM `logistics_records` WHERE `tracking_number` = 'DB0005566778899'),
    '2026-04-11 08:40:00',
    '货物已到达杭州派送网点，正在安排大件派送。'
  ),
  (
    (SELECT `id` FROM `logistics_records` WHERE `tracking_number` = 'DB0005566778899'),
    '2026-04-10 22:15:00',
    '货物已到达杭州转运中心。'
  ),
  (
    (SELECT `id` FROM `logistics_records` WHERE `tracking_number` = 'DB0005566778899'),
    '2026-04-10 09:20:00',
    '佛山仓已发货，德邦物流已揽收。'
  );

INSERT INTO `refund_requests` (
  `refund_id`, `order_id`, `operator`, `reason`, `status`, `status_desc`, `created_at`
) VALUES
  (
    'R202604070001',
    (SELECT `id` FROM `orders` WHERE `order_id` = 'A20260405003'),
    'system',
    '铺贴前发现与预期花色不符，申请退货',
    'completed',
    '退款已完成，款项已原路退回。',
    '2026-04-07 09:30:00'
  ),
  (
    'R202604100002',
    (SELECT `id` FROM `orders` WHERE `order_id` = 'B20260401002'),
    'system',
    '运输破损，其中 3 片边角磕碰，申请退款',
    'processing',
    '退款申请正在审核中，已同步开箱验收记录。',
    '2026-04-10 16:20:00'
  );

INSERT INTO `shipping_urge_requests` (
  `urge_id`, `order_id`, `operator`, `reason`, `status`, `status_desc`, `created_at`
) VALUES
  (
    'U202604100001',
    (SELECT `id` FROM `orders` WHERE `order_id` = 'A20260410001'),
    'system',
    '工地即将进场铺贴，希望尽快发货',
    'submitted',
    '发货提醒已创建，仓储部会优先核对批次并安排发出。',
    '2026-04-10 18:00:00'
  ),
  (
    'U202604070002',
    (SELECT `id` FROM `orders` WHERE `order_id` = 'C20260406001'),
    'system',
    '工期紧张，希望加快发货',
    'submitted',
    '发货提醒已创建，仓储部会优先核对批次并安排发出。',
    '2026-04-07 10:15:00'
  );
