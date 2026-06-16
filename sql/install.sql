CREATE TABLE IF NOT EXISTS `blixt_mokia_numbers` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(64) NOT NULL,
  `phone_number` varchar(20) NOT NULL,
  `display_name` varchar(64) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `citizenid` (`citizenid`),
  UNIQUE KEY `phone_number` (`phone_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `blixt_mokia_contacts` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `owner_citizenid` varchar(64) NOT NULL,
  `name` varchar(32) NOT NULL,
  `phone_number` varchar(20) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `owner_citizenid` (`owner_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `blixt_mokia_messages` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `sender_number` varchar(20) NOT NULL,
  `receiver_number` varchar(20) NOT NULL,
  `content` varchar(160) NOT NULL,
  `is_read` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `sender_receiver` (`sender_number`, `receiver_number`),
  KEY `receiver_sender` (`receiver_number`, `sender_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `blixt_mokia_call_history` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `owner_number` varchar(20) NOT NULL,
  `other_number` varchar(20) NOT NULL,
  `direction` enum('incoming','outgoing') NOT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'ended',
  `duration` int(11) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `owner_number` (`owner_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
