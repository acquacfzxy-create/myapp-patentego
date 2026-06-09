#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
创建准确的JSON分类到章节的映射关系
基于实际的章节配置（chapter_config.dart）
"""

import json
import sqlite3
import os

# 基于实际章节配置的准确映射
# JSON分类 -> 章节ID (基于 chapter_config.dart)
JSON_TO_CHAPTER_MAPPING = {
    # 章节 1: Segnaletica stradale (交通标志)
    "segnali-pericolo": 1,  # 危险标志
    "segnali-divieto": 1,  # 禁止标志
    "segnali-obbligo": 1,  # 义务标志
    "segnali-precedenza": 1,  # 优先标志
    "segnali-indicazione": 1,  # 指示标志
    "segnaletica-orizzontale-ostacoli": 1,  # 水平标志和障碍物
    "segnali-complementari-cantiere": 1,  # 补充标志和工地
    "pannelli-integrativi": 1,  # 补充面板

    # 章节 2: Precedenza (优先权)
    "precedenza-incroci": 2,  # 路口优先权

    # 章节 3: Sosta e fermata (停车与停止)
    "fermata-sosta-arresto": 3,  # 停车、停止和静止

    # 章节 4: Velocità (速度)
    "limiti-di-velocita": 4,  # 速度限制

    # 章节 5: Sorpasso (超车)
    "sorpasso": 5,  # 超车

    # 章节 6: Distanza di sicurezza (安全距离)
    "distanza-di-sicurezza": 6,  # 安全距离

    # 章节 7: Incroci (交叉路口)
    "definizioni-generali-doveri-strada": 7,  # 一般定义和道路义务

    # 章节 8: Curve e cambiamenti di carreggiata (弯道与变道)
    "norme-di-circolazione": 8,  # 交通规则（部分）

    # 章节 9: Veicoli e loro caratteristiche (车辆及其特征)
    "elementi-veicolo-manutenzione-comportamenti": 9,  # 车辆要素、维护和行为

    # 章节 10: Documenti di circolazione (行驶证件)
    "patente-punti-documenti": 10,  # 驾照、分数和文件

    # 章节 11: Guida in condizioni difficili (困难条件下的驾驶)
    "incidenti-stradali-comportamenti": 11,  # 道路事故和行为

    # 章节 12: Comportamento in caso di incidente (事故处理)
    "alcool-droga-primo-soccorso": 12,  # 酒精、毒品和急救

    # 章节 13: Limiti e divieti (限制与禁止)
    "norme-varie-autostrade-pannelli": 13,  # 各种规则、高速公路和面板

    # 章节 14: Segnali luminosi (交通信号灯)
    "semafori-vigili": 14,  # 信号灯和交警
    "luci-dispositivi-acustici": 14,  # 灯光和声音设备

    # 章节 15: Regole generali di comportamento (一般行为规则)
    "cinture-casco-sicurezza": 15,  # 安全带、头盔和安全

    # 章节 16: Norme per la circolazione dei veicoli (车辆通行规则)
    # 这个分类在JSON中可能被分散到多个分类中，需要进一步分析

    # 章节 22: Guida ecologica (环保驾驶)
    "consumi-ambiente-inquinamento": 22,  # 消耗、环境和污染

    # 章节 23: Uso delle cinture di sicurezza (安全带的使用)
    # 已经在章节15中，可能需要调整

    # 章节 其他: 需要进一步分析
    "responsabilita-civile-penale-e-assicurazione": 24,  # 民事责任、刑事责任和保险（可能是章节24的一部分）
}

def match_by_question_content():
    """通过题目内容匹配（更准确但更慢）"""
    pass  # 这需要更复杂的逻辑，暂时不实现

if __name__ == '__main__':
    print("=" * 70)
    print("📋 准确的章节映射配置")
    print("=" * 70)

    print("\n当前映射关系:")
    for json_cat, chapter_id in sorted(JSON_TO_CHAPTER_MAPPING.items(), key=lambda x: x[1]):
        print(f"  章节 {chapter_id:2d}: {json_cat}")

    print("\n⚠️  注意：这个映射关系需要根据实际情况调整！")
    print("=" * 70)

